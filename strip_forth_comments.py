#!/usr/bin/env python

input_filename = './kernel/f64.f'
comment_types = ['slash', 'parenthesis']
in_comment = 'none'
pos = 0
p_depth = 0
pcomments_active = False
intermediate = []
skip = False

with open(input_filename, mode='r', newline='', encoding='utf-8') as infile:
	for line in infile:
		if line == '( Now we can nest ( ... ) as much as we want )\n':
			pcomments_active = True
		if '." 0BRANCH ( "' in line:
			intermediate.append('." 0BRANCH ( "')
			skip = True
		if '." BRANCH ( "' in line:
			intermediate.append('." BRANCH ( "')
			skip = True
		if '." CATCH ( DSP="' in line:
			intermediate.append('." CATCH ( DSP="')
			skip = True
		if line == ': \'\\n\' 10 ;\n':
			intermediate.append(line)
			skip = True
		if line == ': CR \'\\n\' EMIT ;\n':
			intermediate.append(line)
			skip = True
		if line[0] == '\\':
			skip = True
		if line[0] == '\n':
			skip = True
		if skip == False:
			newline = ''
			for c in line:
				if c == '\\' and in_comment == 'none':
					in_comment = 'slash'
				if pcomments_active and c == '(' and in_comment != 'slash':
					in_comment = 'parenthesis'
					p_depth += 1
				if c == '\n':
					pos = 0
					if in_comment == 'slash':
						in_comment = 'none'
				if in_comment not in comment_types:
					newline += c
				if c == '\n':
					if newline != '\n':
						intermediate.append(newline)
				if pcomments_active and c == ')' and in_comment == 'parenthesis':
					p_depth -= 1
					if p_depth == 0:
						in_comment = 'none'
		skip = False
for l in intermediate:
	to_print = l.strip()
	if to_print != '':
		print(to_print.replace('  ', ' '))