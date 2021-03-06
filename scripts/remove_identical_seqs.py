#!/usr/bin/python
"""remove duplicate sequences from a FASTA file based on a list of identical seqeunces"""
import sys

nfastain = sys.argv[1]
nfidentseq = sys.argv[2]
nfastaout = sys.argv[3]

lredundant = []
curfam = None
with open(nfidentseq, 'r') as fidentseq:
	for line in fidentseq:
		#~ fam, prot = line.rstrip('\n').split('\t')
		#~ if fam == curfam:
			#~ lredundant.append(prot)
		#~ else:
			#~ curfam = fam
		prots = line.rstrip('\n').split('\t')
		lredundant += prots[1:]

print "listed %d redundant sequences in dataset"%len(lredundant)
sredundant = set(lredundant)
print "generated hash index"
fastain = open(nfastain, 'r')
fastaout = open(nfastaout, 'w')
print "parsing redundant sequence fasta"
w = True
nnrseq = 0
for line in fastain:
	if line.startswith('>'):
		prot = line.strip('>\n').split(' ', 1)[0]
		if prot not in sredundant:
			w = True
			nnrseq += 1
		else:
			w = False
	if w:
		fastaout.write(line)

print "filtered %d non-redundant sequences"%nnrseq


fastain.close()
fastaout.close()
