( f64OS TCP/IP Network Stack & Intel e1000 Driver - net.f               )
( Usage:  INCLUDE net.f                                                 )
(                                                                       )
( Implements:                                                           )
(   - PCI bus scanner & Intel 82540EM [e1000, 8086:100e] DMA driver     )
(   - Ethernet II framing & Big-Endian network byte order helpers       )
(   - ARP cache, request/reply, and gateway routing                     )
(   - IPv4 packet assembly, parsing, and RFC 1071 checksums             )
(   - ICMP Echo Request [PING] and automatic Echo Reply                 )
(   - UDP datagrams and DNS A-record client [DNS-LOOKUP]                )
(   - Full TCP client/server state machine [TCP-CONNECT, TCP-SEND,      )
(     TCP-RECV, TCP-CLOSE] and HTTP/1.0 client [HTTP-GET]               )

DECIMAL

HERE @ LATEST @
CONSTANT NET-ORIG-LATEST
CONSTANT NET-ORIG-HERE

( --- Bitwise Shift & Big-Endian Helpers ------------------------------ )

: NLSHIFT ( x n -- x<<n )
    DUP 0> IF 0 DO DUP + LOOP ELSE DROP THEN
;

: N1RSHIFT ( u -- u>>1 )
    DUP 0< IF
        1 63 NLSHIFT INVERT AND 2 / 1 62 NLSHIFT OR
    ELSE
        2 /
    THEN
;

: NRSHIFT ( u n -- u>>n )
    DUP 0> IF 0 DO N1RSHIFT LOOP ELSE DROP THEN
;

: BE16@ ( addr -- u16 )
    DUP C@ 256 * SWAP 1+ C@ OR
;

: BE16! ( u16 addr -- )
    OVER 8 NRSHIFT 255 AND OVER C!
    1+ SWAP 255 AND SWAP C!
;

: BE32@ ( addr -- u32 )
    DUP BE16@ 65536 * SWAP 2 + BE16@ OR
;

: BE32! ( u32 addr -- )
    OVER 16 NRSHIFT 65535 AND OVER BE16!
    2 + SWAP 65535 AND SWAP BE16!
;

( Construct 32-bit IPv4 address from 4 octets: a b c d -- ip32 )
: IP4 ( a b c d -- ip32 )
    SWAP 256 * OR
    SWAP 65536 * OR
    SWAP 16777216 * OR
;

: .IP ( ip32 -- )
    BASE @ SWAP DECIMAL
    DUP 24 NRSHIFT 255 AND 0 .R '.' EMIT
    DUP 16 NRSHIFT 255 AND 0 .R '.' EMIT
    DUP 8  NRSHIFT 255 AND 0 .R '.' EMIT
    255 AND 0 .R SPACE
    BASE !
;

: .MAC ( addr -- )
    BASE @ SWAP HEX
    6 0 DO
        DUP I + C@ 2 ZU.R
        I 5 < IF ':' EMIT THEN
    LOOP
    DROP SPACE
    BASE !
;

( Read current PIT tick counter from KSERVICES )
: NET-TICKS ( -- ticks ) KSERVICES 8 + @ @ ;

: NET-WAIT-MS ( ticks -- )
    NET-TICKS +
    BEGIN NET-TICKS OVER < WHILE REPEAT
    DROP
;

( --- Network Configuration [QEMU SLIRP Defaults] --------------------- )

0 VALUE MY-IP
0 VALUE GW-IP
0 VALUE DNS-IP
0 VALUE NET-MASK

6 ALLOT CONSTANT MY-MAC
6 ALLOT CONSTANT BCAST-MAC
255 BCAST-MAC 0 + C!  255 BCAST-MAC 1 + C!  255 BCAST-MAC 2 + C!
255 BCAST-MAC 3 + C!  255 BCAST-MAC 4 + C!  255 BCAST-MAC 5 + C!

( --- PCI Configuration & Intel e1000 NIC Driver ---------------------- )

HEX
3FE00000 VALUE E1000-MMIO
DECIMAL

0 VALUE E1000-DEV
0 VALUE E1000-BAR0
0 VALUE NET-READY

: PCI-ADDR ( bus dev fn reg -- addr )
    252 AND
    SWAP 256 * OR
    SWAP 2048 * OR
    SWAP 65536 * OR
    2147483648 OR
;

: PCI@ ( bus dev fn reg -- val32 )
    PCI-ADDR 3320 OUTL 3324 INL
;

: PCI! ( val32 bus dev fn reg -- )
    PCI-ADDR 3320 OUTL 3324 OUTL
;

: E1000@ ( reg -- val32 ) E1000-MMIO + L@ ;
: E1000! ( val32 reg -- ) E1000-MMIO + L! ;

( Allocate 16-byte aligned RX and TX descriptor rings & packet buffers )
HERE @ 15 + 15 INVERT AND HERE !
128 ALLOT CONSTANT RX-RING
128 ALLOT CONSTANT TX-RING
16384 ALLOT CONSTANT RX-BUFS
16384 ALLOT CONSTANT TX-BUFS
2048  ALLOT CONSTANT PKT-OUT

0 VALUE RX-CUR
0 VALUE TX-CUR

: E1000-INIT ( -- flag )
    -1 TO E1000-DEV
    32 0 DO
        0 I 0 0 PCI@
        269385862 = IF I TO E1000-DEV LEAVE THEN
    LOOP
    E1000-DEV 0< IF
        ." e1000 NIC not found on PCI bus." CR
        FALSE EXIT
    THEN

    ( Map BIOS BAR0 physical page into PD[511] at virtual 0x3FE00000 )
    0 E1000-DEV 0 16 PCI@ 15 INVERT AND TO E1000-BAR0
    E1000-BAR0 2097151 INVERT AND 155 OR 16376 !
    1071644672 E1000-BAR0 2097151 AND + TO E1000-MMIO
    7          0 E1000-DEV 0 4  PCI!

    ( Disable interrupts and set Link Up [SLU | ASDE] )
    4294967295 216 E1000!
    0 E1000@ 96 OR 0 E1000!
    192 E1000@ DROP

    ( Read 6-byte MAC address from RAL0 [0x5400] and RAH0 [0x5404] )
    21504 E1000@ MY-MAC L!
    21508 E1000@ 65535 AND MY-MAC 4 + W!

    ( Initialize 8 RX descriptors )
    RX-RING 128 ZERO-MEM
    8 0 DO
        RX-BUFS I 2048 * +  RX-RING I 16 * +  !
    LOOP
    0 TO RX-CUR
    RX-RING 10240 E1000!
    0       10244 E1000!
    128     10248 E1000!
    0       10256 E1000!
    7       10264 E1000!
    67141662 256  E1000!

    ( Initialize 8 TX descriptors )
    TX-RING 128 ZERO-MEM
    8 0 DO
        TX-BUFS I 2048 * +  TX-RING I 16 * +  !
        1 TX-RING I 16 * + 12 + C!
    LOOP
    0 TO TX-CUR
    TX-RING 14336 E1000!
    0       14340 E1000!
    128     14344 E1000!
    0       14352 E1000!
    0       14360 E1000!
    6299658 1040  E1000!
    262394  1024  E1000!

    1 TO NET-READY
    TRUE
;

( Transmit raw Ethernet frame at addr of length len )
0 VALUE TX-DESC
0 VALUE TX-LEN

: ETH-SEND ( addr len -- )
    DUP 60 < IF 60 ELSE DUP THEN TO TX-LEN
    TX-BUFS TX-CUR 2048 * +  TX-LEN ZERO-MEM
    TX-BUFS TX-CUR 2048 * +  SWAP CMOVE
    TX-RING TX-CUR 16 * + TO TX-DESC
    TX-LEN TX-DESC 8 + W!
    11     TX-DESC 11 + C!
    0      TX-DESC 12 + C!
    TX-CUR 1+ 7 AND TO TX-CUR
    TX-CUR 14360 E1000!
;

( Poll RX ring for next packet; returns [addr len] or [0] )
0 VALUE RX-DESC
0 VALUE RX-PKT-ADDR
0 VALUE RX-PKT-LEN

: ETH-POLL ( -- addr len | 0 )
    RX-RING RX-CUR 16 * + TO RX-DESC
    RX-DESC 12 + C@ 1 AND IF
        RX-BUFS RX-CUR 2048 * + TO RX-PKT-ADDR
        RX-DESC 8 + W@ TO RX-PKT-LEN
        0 RX-DESC 12 + C!
        RX-CUR 10264 E1000!
        RX-CUR 1+ 7 AND TO RX-CUR
        RX-PKT-ADDR RX-PKT-LEN
    ELSE
        0
    THEN
;

( --- RFC 1071 Internet Checksum -------------------------------------- )

: CSUM-PART ( sum addr len -- sum' )
    BEGIN
        DUP 1 >
    WHILE
        >R DUP BE16@ ROT + SWAP 2 + R> 2 -
    REPEAT
    1 = IF
        C@ 256 * +
    ELSE
        DROP
    THEN
;

: CSUM-FOLD ( sum -- csum16 )
    BEGIN
        DUP 65535 >
    WHILE
        DUP 16 NRSHIFT SWAP 65535 AND +
    REPEAT
    65535 XOR
;

: INET-CSUM ( addr len -- csum16 )
    0 -ROT CSUM-PART CSUM-FOLD
;

( --- ARP Cache & Resolution ------------------------------------------ )

8 CONSTANT ARP-SLOTS
64 ALLOT CONSTANT ARP-IPS
48 ALLOT CONSTANT ARP-MACS
0 VALUE ARP-NEXT

: ARP-STORE ( ip32 mac-addr -- )
    ARP-SLOTS 0 DO
        ARP-IPS I 4 * + L@ 2 PICK = IF
            ARP-MACS I 6 * + 6 CMOVE
            DROP UNLOOP EXIT
        THEN
    LOOP
    SWAP ARP-IPS ARP-NEXT 4 * + L!
    ARP-MACS ARP-NEXT 6 * + 6 CMOVE
    ARP-NEXT 1+ 7 AND TO ARP-NEXT
;

: ARP-FIND ( ip32 -- mac-addr | 0 )
    ARP-SLOTS 0 DO
        ARP-IPS I 4 * + L@ OVER = IF
            DROP ARP-MACS I 6 * + UNLOOP EXIT
        THEN
    LOOP
    DROP 0
;

: NEXT-HOP-IP ( dst-ip -- hop-ip )
    DUP NET-MASK AND  MY-IP NET-MASK AND  = IF
        ( same subnet )
    ELSE
        DROP GW-IP
    THEN
;

: ARP-SEND ( opcode target-mac target-ip -- )
    PKT-OUT 60 ZERO-MEM
    OVER PKT-OUT 0 + 6 CMOVE
    MY-MAC PKT-OUT 6 + 6 CMOVE
    2054 PKT-OUT 12 + BE16!
    1    PKT-OUT 14 + BE16!
    2048 PKT-OUT 16 + BE16!
    6    PKT-OUT 18 + C!
    4    PKT-OUT 19 + C!
    ROT  PKT-OUT 20 + BE16!
    MY-MAC PKT-OUT 22 + 6 CMOVE
    MY-IP  PKT-OUT 28 + BE32!
    SWAP PKT-OUT 32 + 6 CMOVE
    PKT-OUT 38 + BE32!
    PKT-OUT 42 ETH-SEND
;

: ARP-HANDLE ( pkt len -- )
    DROP
    DUP 14 + BE16@ 1 = OVER 16 + BE16@ 2048 = AND IF
        DUP 28 + BE32@  OVER 22 +  ARP-STORE
        DUP 20 + BE16@ 1 =  OVER 38 + BE32@ MY-IP =  AND IF
            2  OVER 22 +  ROT 28 + BE32@  ARP-SEND
        ELSE
            DROP
        THEN
    ELSE
        DROP
    THEN
;

( Forward declaration hook for NET-DISPATCH )
0 VALUE DISPATCH-XT
: NET-POLL ( -- )
    ETH-POLL ?DUP IF
        DISPATCH-XT ?DUP IF EXECUTE ELSE 2DROP THEN
    THEN
;

0 VALUE ARP-TARGET
0 VALUE ARP-DEADLINE

: ARP-RESOLVE ( dst-ip -- mac-addr )
    DUP 4294967295 = IF DROP BCAST-MAC EXIT THEN
    NEXT-HOP-IP TO ARP-TARGET
    ARP-TARGET ARP-FIND ?DUP IF EXIT THEN
    1 BCAST-MAC ARP-TARGET ARP-SEND
    NET-TICKS 100 + TO ARP-DEADLINE
    BEGIN
        NET-POLL
        ARP-TARGET ARP-FIND ?DUP IF EXIT THEN
        NET-TICKS ARP-DEADLINE >
    UNTIL
    BCAST-MAC
;

( --- IPv4 Layer ------------------------------------------------------ )

100 VALUE IP-ID
0 VALUE IP-DST
0 VALUE IP-PROTO
0 VALUE IP-PLEN
0 VALUE IP-PADDR
0 VALUE DST-MAC

: IP-SEND ( payload-addr payload-len proto dst-ip -- )
    TO IP-DST
    TO IP-PROTO
    TO IP-PLEN
    TO IP-PADDR
    IP-DST ARP-RESOLVE TO DST-MAC

    DST-MAC PKT-OUT 0 + 6 CMOVE
    MY-MAC  PKT-OUT 6 + 6 CMOVE
    2048    PKT-OUT 12 + BE16!

    69              PKT-OUT 14 + C!
    0               PKT-OUT 15 + C!
    IP-PLEN 20 +    PKT-OUT 16 + BE16!
    IP-ID           PKT-OUT 18 + BE16!
    1 +TO IP-ID
    16384           PKT-OUT 20 + BE16!
    64              PKT-OUT 22 + C!
    IP-PROTO        PKT-OUT 23 + C!
    0               PKT-OUT 24 + BE16!
    MY-IP           PKT-OUT 26 + BE32!
    IP-DST          PKT-OUT 30 + BE32!
    PKT-OUT 14 + 20 INET-CSUM  PKT-OUT 24 + BE16!

    IP-PLEN 0> IF
        IP-PADDR  PKT-OUT 34 +  IP-PLEN  CMOVE
    THEN
    PKT-OUT  IP-PLEN 34 +  ETH-SEND
;

( --- ICMP Layer [Echo Reply & PING] ---------------------------------- )

512 ALLOT CONSTANT ICMP-BUF
0 VALUE PING-GOT
0 VALUE PING-SEQ
0 VALUE PING-T0
0 VALUE PING-RTT

: ICMP-HANDLE ( ip-hdr ip-len -- )
    20 - >R
    DUP 12 + BE32@ SWAP 20 +      ( src-ip icmp-hdr )
    DUP C@ 8 = IF                 ( Echo Request -> send Echo Reply )
        DUP ICMP-BUF R@ CMOVE
        0 ICMP-BUF C!
        0 ICMP-BUF 2 + BE16!
        ICMP-BUF R@ INET-CSUM ICMP-BUF 2 + BE16!
        DROP
        ICMP-BUF SWAP R> SWAP 1 SWAP IP-SEND
    ELSE DUP C@ 0 = IF            ( Echo Reply )
        6 + BE16@ PING-SEQ = IF
            NET-TICKS PING-T0 - TO PING-RTT
            1 TO PING-GOT
        THEN
        DROP RDROP
    ELSE
        2DROP RDROP
    THEN THEN
;

: PING ( dst-ip -- )
    DUP ." Pinging " .IP ." ... "
    1 +TO PING-SEQ
    ICMP-BUF 16 ZERO-MEM
    8        ICMP-BUF 0 + C!
    0        ICMP-BUF 1 + C!
    4660     ICMP-BUF 4 + BE16!
    PING-SEQ ICMP-BUF 6 + BE16!
    S" f64OS!!" ICMP-BUF 8 + SWAP CMOVE
    ICMP-BUF 16 INET-CSUM ICMP-BUF 2 + BE16!

    0 TO PING-GOT
    NET-TICKS TO PING-T0
    ICMP-BUF 16 1 3 PICK IP-SEND
    DROP

    BEGIN
        NET-POLL
        PING-GOT IF
            ." Reply in " PING-RTT . ." ticks!" CR EXIT
        THEN
        NET-TICKS PING-T0 - 200 >
    UNTIL
    ." Request timed out." CR
;

( --- UDP Layer & DNS Client ------------------------------------------ )

1536 ALLOT CONSTANT UDP-BUF
0 VALUE UDP-RX-PORT
0 VALUE UDP-RX-LEN
576 ALLOT CONSTANT UDP-RX-DATA

: UDP-SEND ( addr len src-port dst-port dst-ip -- )
    >R >R >R
    DUP 8 +                  ( addr len udp-len )
    R> UDP-BUF 0 + BE16!     ( src-port )
    R> UDP-BUF 2 + BE16!     ( dst-port )
    DUP UDP-BUF 4 + BE16!    ( udp-len )
    0   UDP-BUF 6 + BE16!    ( checksum = 0 )
    SWAP >R                  ( addr udp-len, R: dst-ip len )
     SWAP R>                 ( udp-len addr len )
    DUP 0> IF
        UDP-BUF 8 + SWAP CMOVE
    ELSE
        2DROP
    THEN
    UDP-BUF SWAP 17 R> IP-SEND
;

: UDP-HANDLE ( ip-hdr ip-len -- )
    DROP 20 +
    DUP 2 + BE16@ TO UDP-RX-PORT
    DUP 4 + BE16@ 8 - DUP 0> IF
        DUP 576 > IF DROP 576 THEN
        DUP TO UDP-RX-LEN
        SWAP 8 + SWAP UDP-RX-DATA SWAP CMOVE
    ELSE
        2DROP
    THEN
;

( --- DHCP Client [RFC 2131: DISCOVER -> OFFER -> REQUEST -> ACK] ----- )

300 ALLOT CONSTANT DHCP-PKT
0 VALUE DHCP-TYPE
0 VALUE DHCP-OFFER-IP
0 VALUE DHCP-SRV-IP
0 VALUE DHCP-T0
0 VALUE DHCP-SAVED-IP

: DHCP-BUILD-BASE ( -- )
    DHCP-PKT 300 ZERO-MEM
    1          DHCP-PKT 0 + C!
    1          DHCP-PKT 1 + C!
    6          DHCP-PKT 2 + C!
    0          DHCP-PKT 3 + C!
    956560166  DHCP-PKT 4 + BE32!
    32768      DHCP-PKT 10 + BE16!
    MY-MAC     DHCP-PKT 28 + 6 CMOVE
    1669485411 DHCP-PKT 236 + BE32!
;

: DHCP-PARSE-OPTS ( -- )
    0 TO DHCP-TYPE
    240
    BEGIN
        DUP UDP-RX-LEN <
    WHILE
        DUP UDP-RX-DATA + C@
        DUP 255 = IF 2DROP EXIT THEN
        DUP 0= IF
            DROP 1+
        ELSE
            OVER 2 + UDP-RX-DATA +
            SWAP CASE
                53 OF C@ TO DHCP-TYPE ENDOF
                54 OF BE32@ TO DHCP-SRV-IP ENDOF
                1  OF BE32@ TO NET-MASK ENDOF
                3  OF BE32@ TO GW-IP ENDOF
                6  OF BE32@ TO DNS-IP ENDOF
                NIP
            ENDCASE
            DUP 1+ UDP-RX-DATA + C@ 2 + +
        THEN
    REPEAT
    DROP
;

: DHCP-WAIT ( want-type -- flag )
    NET-TICKS TO DHCP-T0
    BEGIN
        NET-POLL
        UDP-RX-LEN 240 >= UDP-RX-PORT 68 = AND IF
            UDP-RX-DATA 0 + C@ 2 =
            UDP-RX-DATA 4 + BE32@ 956560166 = AND
            UDP-RX-DATA 236 + BE32@ 1669485411 = AND IF
                UDP-RX-DATA 16 + BE32@ TO DHCP-OFFER-IP
                UDP-RX-DATA 20 + BE32@ ?DUP IF TO DHCP-SRV-IP THEN
                DHCP-PARSE-OPTS
                DUP DHCP-TYPE = IF DROP TRUE EXIT THEN
            THEN
            0 TO UDP-RX-LEN
        THEN
        NET-TICKS DHCP-T0 - 100 >
    UNTIL
    DROP FALSE
;

: DHCP ( -- flag )
    MY-IP TO DHCP-SAVED-IP
    0 TO MY-IP
    0 TO DHCP-SRV-IP

    ( 1. Broadcast DHCPDISCOVER )
    DHCP-BUILD-BASE
    53  DHCP-PKT 240 + C!  1 DHCP-PKT 241 + C!  1 DHCP-PKT 242 + C!
    55  DHCP-PKT 243 + C!  3 DHCP-PKT 244 + C!
    1   DHCP-PKT 245 + C!  3 DHCP-PKT 246 + C!  6 DHCP-PKT 247 + C!
    255 DHCP-PKT 248 + C!
    0 TO UDP-RX-LEN
    DHCP-PKT 300 68 67 4294967295 UDP-SEND

    2 DHCP-WAIT NOT IF
        10 0 2 15     IP4 TO MY-IP
        10 0 2 2      IP4 TO GW-IP
        10 0 2 3      IP4 TO DNS-IP
        255 255 255 0 IP4 TO NET-MASK
        FALSE EXIT
    THEN

    ( 2. Broadcast DHCPREQUEST for offered IP )
    DHCP-BUILD-BASE
    53            DHCP-PKT 240 + C!  1 DHCP-PKT 241 + C!  3 DHCP-PKT 242 + C!
    50            DHCP-PKT 243 + C!  4 DHCP-PKT 244 + C!
    DHCP-OFFER-IP DHCP-PKT 245 + BE32!
    54            DHCP-PKT 249 + C!  4 DHCP-PKT 250 + C!
    DHCP-SRV-IP   DHCP-PKT 251 + BE32!
    55            DHCP-PKT 255 + C!  3 DHCP-PKT 256 + C!
    1             DHCP-PKT 257 + C!  3 DHCP-PKT 258 + C!  6 DHCP-PKT 259 + C!
    255           DHCP-PKT 260 + C!
    0 TO UDP-RX-LEN
    DHCP-PKT 300 68 67 4294967295 UDP-SEND

    5 DHCP-WAIT DROP
    DHCP-OFFER-IP TO MY-IP
    TRUE
;

( DNS A-Record Resolver over UDP port 53 )
256 ALLOT CONSTANT DNS-PKT
0 VALUE DNS-POS
0 VALUE DNS-LBL-POS

: DNS-ENCODE-NAME ( addr len -- )
    12 TO DNS-POS
    12 TO DNS-LBL-POS
    0 DNS-PKT 12 + C!
    1 +TO DNS-POS
    0 DO
        DUP I + C@
        DUP 46 = IF
            DROP
            DNS-POS DNS-LBL-POS - 1-  DNS-PKT DNS-LBL-POS + C!
            DNS-POS TO DNS-LBL-POS
            0 DNS-PKT DNS-POS + C!
            1 +TO DNS-POS
        ELSE
            DNS-PKT DNS-POS + C!
            1 +TO DNS-POS
        THEN
    LOOP
    DROP
    DNS-POS DNS-LBL-POS - 1-  DNS-PKT DNS-LBL-POS + C!
    0 DNS-PKT DNS-POS + C!
    1 +TO DNS-POS
;

: DNS-SKIP-NAME ( off -- off' )
    BEGIN
        DUP UDP-RX-LEN <
    WHILE
        DUP UDP-RX-DATA + C@
        DUP 0= IF DROP 1+ EXIT THEN
        192 AND 192 = IF 2 + EXIT THEN
        DUP UDP-RX-DATA + C@ 1+ +
    REPEAT
;

0 VALUE DNS-ANC
0 VALUE DNS-T0

: DNS-LOOKUP ( name-addr name-len -- ip32 | 0 )
    DNS-PKT 256 ZERO-MEM
    43981 DNS-PKT 0 + BE16!
    256   DNS-PKT 2 + BE16!
    1     DNS-PKT 4 + BE16!
    DNS-ENCODE-NAME
    1 DNS-PKT DNS-POS + BE16!
    1 DNS-PKT DNS-POS 2 + + BE16!
    DNS-POS 4 + TO DNS-POS

    0 TO UDP-RX-LEN
    DNS-PKT DNS-POS 53000 53 DNS-IP UDP-SEND
    NET-TICKS TO DNS-T0
    BEGIN
        NET-POLL
        UDP-RX-LEN 12 > UDP-RX-PORT 53000 = AND IF
            UDP-RX-DATA 6 + BE16@ TO DNS-ANC
            12 DNS-SKIP-NAME 4 +
            DNS-ANC 0> IF
                DNS-ANC 0 DO
                    DNS-SKIP-NAME
                    DUP UDP-RX-DATA + BE16@ 1 = IF
                        10 + UDP-RX-DATA + BE32@ UNLOOP EXIT
                    THEN
                    DUP 8 + UDP-RX-DATA + BE16@ 10 + +
                LOOP
            THEN
            DROP 0 EXIT
        THEN
        NET-TICKS DNS-T0 - 200 >
    UNTIL
    0
;

( --- TCP Layer [Protocol 6] ------------------------------------------ )

0 CONSTANT TCP-CLOSED
1 CONSTANT TCP-SYN-SENT
2 CONSTANT TCP-ESTABLISHED
3 CONSTANT TCP-CLOSE-WAIT
4 CONSTANT TCP-FIN-WAIT
5 CONSTANT TCP-LISTEN-ST

1  CONSTANT TF-FIN
2  CONSTANT TF-SYN
4  CONSTANT TF-RST
8  CONSTANT TF-PSH
16 CONSTANT TF-ACK

0 VALUE TCP-STATE
0 VALUE TCP-LPORT
0 VALUE TCP-RPORT
0 VALUE TCP-RIP
0 VALUE TCP-SND-NXT
0 VALUE TCP-RCV-NXT
0 VALUE TCP-ACKED

1536 ALLOT CONSTANT TCP-TX-BUF
4096 ALLOT CONSTANT TCP-RX-BUF
0 VALUE TCP-RX-LEN

: TCP-CSUM ( seg-addr seg-len -- csum16 )
    0
    MY-IP 16 NRSHIFT 65535 AND +
    MY-IP 65535 AND +
    TCP-RIP 16 NRSHIFT 65535 AND +
    TCP-RIP 65535 AND +
    6 +
    OVER +
    -ROT CSUM-PART CSUM-FOLD
;

0 VALUE T-FLAGS
0 VALUE T-LEN

: TCP-SEND-SEG ( payload-addr payload-len flags -- )
    TO T-FLAGS
    TO T-LEN
    TCP-TX-BUF 20 ZERO-MEM
    TCP-LPORT   TCP-TX-BUF 0 + BE16!
    TCP-RPORT   TCP-TX-BUF 2 + BE16!
    TCP-SND-NXT TCP-TX-BUF 4 + BE32!
    TCP-RCV-NXT TCP-TX-BUF 8 + BE32!
    80          TCP-TX-BUF 12 + C!
    T-FLAGS     TCP-TX-BUF 13 + C!
    16384       TCP-TX-BUF 14 + BE16!
    0           TCP-TX-BUF 16 + BE16!
    0           TCP-TX-BUF 18 + BE16!

    T-LEN 0> IF
        TCP-TX-BUF 20 + T-LEN CMOVE
    ELSE
        DROP
    THEN

    TCP-TX-BUF T-LEN 20 + DUP >R TCP-CSUM
    TCP-TX-BUF 16 + BE16!

    T-LEN +TO TCP-SND-NXT
    T-FLAGS TF-SYN TF-FIN OR AND IF
        1 +TO TCP-SND-NXT
    THEN

    TCP-TX-BUF R> 6 TCP-RIP IP-SEND
;

0 VALUE TH-ADDR
0 VALUE TH-HLEN
0 VALUE TH-DLEN
0 VALUE TH-FLAGS

: TCP-HANDLE ( ip-hdr ip-len -- )
    TCP-STATE TCP-LISTEN-ST = IF
        OVER 12 + BE32@ TO TCP-RIP
        20 - SWAP 20 + TO TH-ADDR
        TH-ADDR 2 + BE16@ TCP-LPORT <> IF DROP EXIT THEN
        TH-ADDR 13 + C@ TF-SYN AND IF
            TH-ADDR 0 + BE16@ TO TCP-RPORT
            TH-ADDR 4 + BE32@ 1+ TO TCP-RCV-NXT
            NET-TICKS 65536 * 54321 + TO TCP-SND-NXT
            0 TO TCP-RX-LEN
            TCP-ESTABLISHED TO TCP-STATE
            0 0 TF-SYN TF-ACK OR TCP-SEND-SEG
        THEN
        DROP EXIT
    THEN
    OVER 12 + BE32@ TCP-RIP <> IF 2DROP EXIT THEN
    20 - SWAP 20 + TO TH-ADDR
    TH-ADDR 0 + BE16@ TCP-RPORT <>
    TH-ADDR 2 + BE16@ TCP-LPORT <> OR IF DROP EXIT THEN

    TH-ADDR 12 + C@ 4 NRSHIFT 4 * TO TH-HLEN
    TH-HLEN - TO TH-DLEN
    TH-ADDR 13 + C@ TO TH-FLAGS

    TH-FLAGS TF-RST AND IF
        TCP-CLOSED TO TCP-STATE EXIT
    THEN

    TCP-STATE TCP-SYN-SENT = IF
        TH-FLAGS TF-SYN TF-ACK OR AND  TF-SYN TF-ACK OR  = IF
            TH-ADDR 4 + BE32@ 1+ TO TCP-RCV-NXT
            TCP-ESTABLISHED TO TCP-STATE
            0 0 TF-ACK TCP-SEND-SEG
        THEN
        EXIT
    THEN

    TH-FLAGS TF-ACK AND IF
        1 TO TCP-ACKED
    THEN

    TH-DLEN 0> IF
        TH-ADDR 4 + BE32@ TCP-RCV-NXT = IF
            TCP-RX-LEN TH-DLEN + 4096 <= IF
                TH-ADDR TH-HLEN +  TCP-RX-BUF TCP-RX-LEN +  TH-DLEN CMOVE
                TH-DLEN +TO TCP-RX-LEN
            THEN
            TH-DLEN +TO TCP-RCV-NXT
        THEN
        0 0 TF-ACK TCP-SEND-SEG
    THEN

    TH-FLAGS TF-FIN AND IF
        1 +TO TCP-RCV-NXT
        0 0 TF-ACK TCP-SEND-SEG
        TCP-CLOSE-WAIT TO TCP-STATE
    THEN
;

49152 VALUE NEXT-EPH-PORT
0 VALUE TCP-T0

: TCP-CONNECT ( dst-ip dst-port -- flag )
    TO TCP-RPORT
    TO TCP-RIP
    NEXT-EPH-PORT TO TCP-LPORT
    1 +TO NEXT-EPH-PORT
    NET-TICKS 65536 * 12345 + TO TCP-SND-NXT
    0 TO TCP-RCV-NXT
    0 TO TCP-RX-LEN
    TCP-SYN-SENT TO TCP-STATE

    0 0 TF-SYN TCP-SEND-SEG
    NET-TICKS TO TCP-T0
    BEGIN
        NET-POLL
        TCP-STATE TCP-ESTABLISHED = IF TRUE EXIT THEN
        TCP-STATE TCP-CLOSED = IF FALSE EXIT THEN
        NET-TICKS TCP-T0 - 200 >
    UNTIL
    TCP-CLOSED TO TCP-STATE
    FALSE
;

: TCP-SEND ( addr len -- )
    0 TO TCP-ACKED
    TF-PSH TF-ACK OR TCP-SEND-SEG
    NET-TICKS TO TCP-T0
    BEGIN
        NET-POLL
        TCP-ACKED IF EXIT THEN
        NET-TICKS TCP-T0 - 100 >
    UNTIL
;

0 VALUE RX-COPY

: TCP-RECV ( buf maxlen timeout-ticks -- len )
    NET-TICKS + TO TCP-T0
    BEGIN
        NET-POLL
        TCP-RX-LEN 0> IF
            TCP-RX-LEN MIN TO RX-COPY
            TCP-RX-BUF SWAP RX-COPY CMOVE
            TCP-RX-LEN RX-COPY > IF
                TCP-RX-BUF RX-COPY +  TCP-RX-BUF  TCP-RX-LEN RX-COPY -  CMOVE
            THEN
            TCP-RX-LEN RX-COPY - TO TCP-RX-LEN
            RX-COPY EXIT
        THEN
        TCP-STATE TCP-CLOSE-WAIT = TCP-STATE TCP-CLOSED = OR IF
            2DROP 0 EXIT
        THEN
        NET-TICKS TCP-T0 >
    UNTIL
    2DROP 0
;

: TCP-CLOSE ( -- )
    TCP-STATE TCP-ESTABLISHED = TCP-STATE TCP-CLOSE-WAIT = OR IF
        0 0 TF-FIN TF-ACK OR TCP-SEND-SEG
        30 NET-WAIT-MS
        NET-POLL
    THEN
    TCP-CLOSED TO TCP-STATE
;

( --- Packet Dispatcher ----------------------------------------------- )

: (NET-DISPATCH) ( pkt len -- )
    DUP 14 < IF 2DROP EXIT THEN
    OVER 12 + BE16@
    CASE
        2054 OF ARP-HANDLE ENDOF
        2048 OF
            DROP 14 +                 ( ip-hdr )
            DUP 2 + BE16@             ( ip-hdr ip-len )
            OVER 9 + C@
            CASE
                1  OF ICMP-HANDLE ENDOF
                6  OF TCP-HANDLE  ENDOF
                17 OF UDP-HANDLE  ENDOF
                >R 2DROP R>
            ENDCASE
        ENDOF
        >R 2DROP R>
    ENDCASE
;

( --- High-Level Utilities: NET-INFO & HTTP-GET ----------------------- )

: NET-INFO ( -- )
    ." NIC MAC : " MY-MAC .MAC ." (MY-MAC)" CR
    ." Local IP: " MY-IP .IP ." (MY-IP)" CR
    ." Netmask : " NET-MASK .IP ." (NET-MASK)" CR
    ." Gateway : " GW-IP .IP ." (GW-IP)" CR
    ." DNS Srv : " DNS-IP .IP ." (DNS-IP)" CR
;

512 ALLOT CONSTANT HTTP-REQ
0 VALUE HTTP-RLEN
512 ALLOT CONSTANT HTTP-BUF

: HTTP-ADD ( addr len -- )
    DUP 0> IF
        SWAP OVER HTTP-REQ HTTP-RLEN + SWAP CMOVE
        +TO HTTP-RLEN
    ELSE
        2DROP
    THEN
;

: NET-KEY? ( -- flag )
    KSERVICES 32 + @ C@  KSERVICES 40 + @ C@  <>
;

: TCP-ACCEPT ( port -- flag )
    TO TCP-LPORT
    0 TO TCP-RIP
    0 TO TCP-RPORT
    0 TO TCP-RX-LEN
    TCP-LISTEN-ST TO TCP-STATE
    ." Listening on TCP port " TCP-LPORT . ." (press any key to abort)..." CR
    BEGIN
        NET-POLL
        TCP-STATE TCP-ESTABLISHED = IF
            ." Connected from " TCP-RIP .IP ." :" TCP-RPORT . CR
            TRUE EXIT
        THEN
        NET-KEY?
    UNTIL
    KEY-RAW DROP
    TCP-CLOSED TO TCP-STATE
    FALSE
;

: HTTP-PRINT ( addr len -- )
    DUP 0> IF
        0 DO
            DUP I + C@
            DUP 13 <> IF EMIT ELSE DROP THEN
        LOOP
    THEN
    DROP
;

: HTTP-GET ( dst-ip port path-addr path-len -- )
    2SWAP
    ." Connecting to " OVER .IP ." :" DUP . CR
    TCP-CONNECT NOT IF
        2DROP ." Connection failed." CR EXIT
    THEN
    0 TO HTTP-RLEN
    S" GET " HTTP-ADD
    HTTP-ADD
    S"  HTTP/1.0" HTTP-ADD
    13 HTTP-REQ HTTP-RLEN + C!  1 +TO HTTP-RLEN
    10 HTTP-REQ HTTP-RLEN + C!  1 +TO HTTP-RLEN
    S" Host: f64OS" HTTP-ADD
    13 HTTP-REQ HTTP-RLEN + C!  1 +TO HTTP-RLEN
    10 HTTP-REQ HTTP-RLEN + C!  1 +TO HTTP-RLEN
    13 HTTP-REQ HTTP-RLEN + C!  1 +TO HTTP-RLEN
    10 HTTP-REQ HTTP-RLEN + C!  1 +TO HTTP-RLEN

    HTTP-REQ HTTP-RLEN TCP-SEND
    BEGIN
        HTTP-BUF 512 100 TCP-RECV
        ?DUP
    WHILE
        HTTP-BUF SWAP HTTP-PRINT
    REPEAT
    CR TCP-CLOSE
;

: NET-UNLOAD ( -- )
    NET-ORIG-LATEST LATEST !
    NET-ORIG-HERE   HERE !
    ." TCP/IP stack unloaded (" UNUSED . ." cells free)" CR
;

: INIT-NET ( -- )
    ['] (NET-DISPATCH) TO DISPATCH-XT
    E1000-INIT IF
        ." Acquiring IP via DHCP... "
        DHCP IF ." OK" CR ELSE ." Fallback to static" CR THEN
        ." f64OS TCP/IP stack ready." CR
        NET-INFO
    THEN
;

INIT-NET
