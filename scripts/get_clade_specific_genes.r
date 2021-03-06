#!/usr/bin/Rscript --vanilla
library('RSQLite')
library('getopt')

# clade definition file format example :
# (order of columns is irrelevant; only 'clade' and 'sisterclade' fields are mandatory; note there is no column name for the row id field (first actual column with 'cladeA' etc.))
# relaxed specific presence pattern can be detected by specifying values of parameters 'maxabsin' and 'maxpresout' > 0
# relaxed specific absence pattern can be detected by specifying values of parameters 'maxpresin' and 'maxabsout' > 0

# such file is automatically produced durring Pantagruel pipeline task 08.clade_specific_genes
#	name	maxabsin	maxpresout	maxpresin	maxabsout	clade	sisterclade
#cladeA	"P. endolithicum"	0	0	0	0	REJC140,REQ54	RFYW14,RHAB21,RKHAN,RHIZOB27,RNT25,RTCK,PSEPEL1,PSEPEL2,RHIMAR
#cladeB	"P. banfieldii"	0	0	0	0	RHIZOB27,RNT25,RTCK	RFYW14,RHAB21,RKHAN,REJC140,REQ54,PSEPEL1,PSEPEL2,RHIMAR
#cladeC	"P. halotolerans"	0	0	0	0	RFYW14,RHAB21,RKHAN	RHIZOB27,RNT25,RTCK,REJC140,REQ54,PSEPEL1,PSEPEL2,RHIMAR
#cladeD	"P. pelagicum"	0	0	0	0	PSEPEL1,PSEPEL2,RHIMAR	RFYW14,RHAB21,RKHAN,RHIZOB27,RNT25,RTCK,REJC140,REQ54
#cladeE	"Pban+Phalo"	0	0	0	0	RFYW14,RHAB21,RKHAN,RHIZOB27,RNT25,RTCK	REJC140,REQ54,PSEPEL1,PSEPEL2,RHIMAR
#cladeF	"Pban+Phalo+Pendo"	0	0	0	0	RFYW14,RHAB21,RKHAN,RHIZOB27,RNT25,RTCK,REJC140,REQ54	PSEPEL1,PSEPEL2,RHIMAR
#cladeG	"Psedorhizobium"	0	0	0	0	RFYW14,RHAB21,RKHAN,RHIZOB27,RNT25,RTCK,REJC140,REQ54,PSEPEL1,PSEPEL2,RHIMAR	

genesetscopes = c("reprseq", "allseq")
abspres = c("abs", "pres") ; names(abspres) = abspres
presabs = c("pres", "abs") ; names(presabs) = abspres

cargs = commandArgs(trailing=T)

##### main
spec = matrix(c(
  'gene_count_matrix',    'm', 1, "character", "path of metrix of counts of each gene family (or gene family_ortholog group id) (rows) in each genome (columns)",
  'sqldb',                'd', 1, "character", "path to SQLite database file",
  'clade_defs',           'C', 1, "character", "path to file describing clade composition; this must be a (tab-delimited) table file with named rows and a header with the following collumns: (mandatory:) 'clade', 'siterclade', (facultative:) 'name', 'maxabsin', 'maxpresout', 'maxpresin' and 'maxabsout'",
  'outrad',               'o', 1, "character", "path to output dir+file prefix for output files",
  'restrict_to_genomes',  'g', 2, "character", "(optional) path to file listing the genomes (UniProt-like codes) to which the analysis will be restricted",
  'og_col_id',            'c', 2, "integer",   "orthologous group collection id in SQL database; if not provided, will only use the homologous family mapping of genes (coarser homology mapping, meaning stricter clade-specific gene definition)",
  'ass_to_code',          'a', 2, "character", "(optional) path to file providing correspondency between assembly ids and UniProt-like genome codes; only if the input matrix has assembly ids in column names (deprecated)",
  'preferred_genomes',    'p', 2, "character", "(optional) comma-separated list of codes of preferred genomes which CDS info will be reported in reference tables (when part of the focal clade); genomes are selected in priority order as listed: 1st_preferred, 2nd_preferred, etc.",
  'interesting_families', 'f', 2, "character", "(optional) comma-separated list of gene families for which detail of presence/absence distribution will be printed out"
), byrow=TRUE, ncol=5);
opt = getopt(spec, opt=commandArgs(trailingOnly=T))

nffamgenomemat = opt$gene_count_matrix
sqldb = opt$sqldb
nfcladedef = opt$clade_defs
outfilerad = opt$outrad
ogcolid = opt$og_col_id
nfrestrictlist = opt$restrict_to_genomes
nflasscode = opt$ass_to_code
if (!is.null(opt$preferred_genomes)){
	preferredgenomes = strsplit(opt$preferred_genomes, split=',')[[1]]
}else{
	preferredgenomes = c()
}
if (!is.null(opt$interesting_families)){
	interstfams = strsplit(opt$interesting_families, split=',')[[1]]
}else{
	interstfams = c()
}
if ( is.null(ogcolid) | ogcolid < 0 ){
	print("will only use the homologous family mapping of genes (coarser homology mapping and stricter clade-specific gene finding)", quote=F)
}else{
	print("use ortholog classification of homologous genes", quote=F)
}


# output files
nfabspresmat = sprintf("%s_gene_abspres.mat.RData", outfilerad)
nfoutspege = sapply(abspres, function(x){ sprintf("%s_specific_%s_genes.tab", outfilerad, x) })
bnoutspege = sapply(abspres, function(x){ sprintf("%s_specific_%s_genes", basename(outfilerad), x) })
diroutspegedetail = sprintf("%s_specific_genes.tables_byclade_goterms_pathways", outfilerad)
dir.create(diroutspegedetail, showWarnings=F)

cladedefcsv = read.table(nfcladedef, sep='\t', header=T, row.names=1, stringsAsFactors=F)
cladedefs = apply(cladedefcsv[,c('clade', 'sisterclade')], 1, strsplit, split=',')

for (i in 1:length(cladedefs)){
	cla = names(cladedefs)[i]
	cladedefs[[cla]]$name = ifelse(!is.null(cladedefcsv$name), cladedefcsv$name[i], "")
	cladedefs[[cla]]$maxabsin = ifelse(!is.null(cladedefcsv$maxabsin), cladedefcsv$maxabsin[i], 0)
	cladedefs[[cla]]$maxpresout = ifelse(!is.null(cladedefcsv$maxpresout), cladedefcsv$maxpresout[i], 0)
	cladedefs[[cla]]$maxpresin = ifelse(!is.null(cladedefcsv$maxpresin), cladedefcsv$maxpresin[i], 0)
	cladedefs[[cla]]$maxabsout = ifelse(!is.null(cladedefcsv$maxabsout), cladedefcsv$maxabsout[i], 0)
}

# load gene presence / absence data
if (file.exists(nfabspresmat)){
	load(nfabspresmat)
}else{
	genocount = data.matrix(read.table(file=nffamgenomemat))
	if (!is.null(nfrestrictlist)){
		restrictgenomelist = readLines(nfrestrictlist)
		if (!is.null(nflasscode)){
			lasscode = read.table(nflasscode, row.names=1, stringsAsFactors=F)
			colnames(genocount) = lasscode[colnames(genocount),1]
		}
	#~ 	print(setdiff(restrictgenomelist, colnames(genocount)))
		genocount = genocount[,restrictgenomelist]
		gc()
	}
	save(genocount, file=nfabspresmat)
}

# compute gene sets
specificPresGenes = lapply(cladedefs, function(cladedef){
	# relaxed specific presence is allowed by 'maxabsin' and 'maxpresout' parameters
	allpres = apply(genocount[,cladedef$clade,drop=F], 1, function(x){ length(which(x==0))<=cladedef$maxabsin })
	allabssis = apply(genocount[,cladedef$sisterclade,drop=F], 1, function(x){ length(which(x>0))<=cladedef$maxpresout })
	return(which(allpres & allabssis))
})

specificAbsGenes = lapply(cladedefs, function(cladedef){
	# relaxed specific absence is allowed by 'maxpresin' and 'maxabsout' parameters
	allabs = apply(genocount[,cladedef$clade,drop=F], 1, function(x){ length(which(x>0))<=cladedef$maxpresin })
	allpressis = apply(genocount[,cladedef$sisterclade,drop=F], 1, function(x){ length(which(x==0))<=cladedef$maxabsout })
	return(which(allabs & allpressis))
})

specifisets = list(specificAbsGenes, specificPresGenes) ; names(specifisets) = abspres

dbcon = dbConnect(SQLite(), sqldb)

cladedefwritesep = paste(c(rep('\t', 4), rep('  ...  \t', 3)), sep='', collapse='')

today = Sys.Date()
for (ab in abspres){
	write( paste("#", c(format(today, format="%B %d %Y"), "Pantagruel version:", system("cd ${ptgscripts} ; git log | head -n 3", intern=T), "- - - - -")), file=nfoutspege[[ab]], append=F)
}

for (i in 1:length(cladedefs)){
	cla = names(cladedefs)[i]
	cladedef = cladedefs[[cla]]
	
	for (ab in abspres){
		write(sprintf("# %s %s", cla, cladedef$name), file=nfoutspege[[ab]], append=T)
		write( paste(sprintf("# gene families %sent in all genomes but %d of clade:", abspres[ab], cladedef$maxabsin), cladedefcsv[cla,'clade'], sep=cladedefwritesep), file=nfoutspege[[ab]], append=T)
		write( paste(sprintf("# and %sent in all but %d genomes of sister clade:", presabs[ab], cladedef$maxpresout), cladedefcsv[cla,'sisterclade'], sep=cladedefwritesep), file=nfoutspege[[ab]], append=T)
	
		specset = specifisets[[ab]][[cla]]
		ncsg = length(specset)
		if (ncsg==0){
			write("# no specific gene found", file=nfoutspege[[ab]], append=T)
			print(sprintf("%s: '%s'; no specific %sent gene found", cla, cladedef$name, abspres[ab]), quote=F)
		}else{
			for (interstfam in interstfams){
				if (interstfam %in% rownames(genocount)[specset]){
					print(sprintf("%s family:", interstfam), quote=F)
					if (ab=="pres"){ abspresin = which(genocount[interstfam,cladedef$clade,drop=F]==0)
					}else{ abspresin = which(genocount[interstfam,cladedef$clade,drop=F]>0) }
					print(sprintf("  %sent in %d clade genomes:        %s", abspres[[ab]], length(abspresin), paste(cladedef$clade[abspresin], sep=' ', collapse=' ')), quote=F)
					if (ab=="pres"){ abspresout = which(genocount[interstfam,cladedef$sisterclade,drop=F]>0)
					}else{ abspresout = which(genocount[interstfam,cladedef$sisterclade,drop=F]==0) }
					print(sprintf("  %sent in %d sister clade genomes: %s", presabs[[ab]], length(abspresout), paste(cladedef$sisterclade[abspresout], sep=' ', collapse=' ')), quote=F)
				}
			}
			spefamogs = as.data.frame(t(sapply(strsplit(rownames(genocount)[specset], split='-'), function(x){ if (length(x)==2) return(x) else return(c(x, NA)) })), stringsAsFactors=F)
			spefamogs[,2] = as.numeric(spefamogs[,2]) ; colnames(spefamogs) = c("gene_family_id", "og_id")
			dbBegin(dbcon)
			dbWriteTable(dbcon, "specific_genes", spefamogs, temporary=T)
			write.table(spefamogs, file=file.path(diroutspegedetail, paste(bnoutspege[[ab]], cla, "spegene_fams_ogids.tab", sep='_')), sep='\t', quote=F, row.names=F, col.names=T, append=F)
			# choose adequate reference genome
			if (ab=="pres"){ occgenomes = cladedef$clade
			}else{ occgenomes = cladedef$sisterclade }
			refgenome = NULL
			for (prefgenome in preferredgenomes){
				if (prefgenome %in% occgenomes){
					refgenome = prefgenome
					break
				}
			}
			if (is.null(refgenome)){ refgenome = min(occgenomes) }
			print(sprintf("%s: '%s'; %d clade-specific %sent genes; ref genome: %s", cla, cladedef$name, ncsg, abspres[ab], refgenome), quote=F)
			dbExecute(dbcon, "DROP TABLE IF EXISTS spegeneannots;")
			creaspegeneannots = paste( c(
			 "CREATE TABLE spegeneannots AS ",
			 "SELECT gene_family_id, og_id, genomic_accession, code, locus_tag, cds_code, cds_begin, cds_end, nr_protein_id, product",
			 "FROM (",
			 "  SELECT gene_family_id, og_id, ortholog_col_id, coding_sequences.* FROM specific_genes",
			 "   INNER JOIN orthologous_groups USING (gene_family_id, og_id)",
			 "   INNER JOIN coding_sequences USING (cds_code, gene_family_id)",
			 " UNION",
			 "  SELECT gene_family_id, og_id, ortholog_col_id, coding_sequences.* FROM specific_genes",
			 "   LEFT JOIN orthologous_groups USING (gene_family_id, og_id)",
			 "   INNER JOIN coding_sequences USING (gene_family_id)",
			 "   WHERE og_id IS NULL ) as famog2cds",
			 "INNER JOIN proteins USING (nr_protein_id)",
			 "INNER JOIN replicons USING (genomic_accession)",
			 "INNER JOIN assemblies USING (assembly_id)",
			 sprintf("WHERE code IN ( '%s' )", paste(occgenomes, collapse="','", sep='')),
			 "AND (ortholog_col_id = :o OR ortholog_col_id IS NULL) ;"),
			 collapse=" ")
#~ 			print(creaspegeneannots)
			dbExecute(dbcon, creaspegeneannots, params=list(o=ogcolid))
			dbExecute(dbcon, "DROP TABLE specific_genes;")
			genesetclauses = list(sprintf("WHERE code='%s' AND", refgenome), "WHERE") ; names(genesetclauses) = genesetscopes
			for (genesetscope in genesetscopes){
				gsc = genesetclauses[[genesetscope]] # = "WHERE [clause AND]"
#~ 				print(gsc)
				spegeneinfo = dbGetQuery(dbcon, paste( c(
				"SELECT gene_family_id, og_id, cds_code, genomic_accession, locus_tag, cds_begin, cds_end, product", 
				"FROM spegeneannots", 
				gsc, "1 ORDER BY locus_tag ;"), collapse=" "))
				spegeneinfoplus = dbGetQuery(dbcon, paste( c(
				 "SELECT distinct gene_family_id, og_id, cds_code, genomic_accession, locus_tag, cds_begin, cds_end, product, interpro_id, interpro_description, go_terms, pathways",
				 "FROM spegeneannots",
				 "LEFT JOIN functional_annotations USING (nr_protein_id)",
				 "LEFT JOIN interpro_terms USING (interpro_id)", 
				 gsc, "1 ORDER BY locus_tag ;"), collapse=" "))
				spegallgoterms = dbGetQuery(dbcon, paste( c(
				 "SELECT distinct gene_family_id, og_id, cds_code, genomic_accession, locus_tag, go_id",
				 "FROM spegeneannots",
				 "LEFT JOIN functional_annotations USING (nr_protein_id)",
				 "LEFT JOIN interpro2GO USING (interpro_id)",
				 gsc, "go_id NOT NULL ORDER BY locus_tag ;"), collapse=" "))
				spegallpathways = dbGetQuery(dbcon, paste( c(
				 "SELECT distinct gene_family_id, og_id, cds_code, genomic_accession, locus_tag, pathway_db, pathway_id",
				 "FROM spegeneannots",
				 "LEFT JOIN functional_annotations USING (nr_protein_id)",
				 "LEFT JOIN interpro2pathways USING (interpro_id)",
				 gsc, "pathway_id NOT NULL ORDER BY locus_tag ;"), collapse=" "))
				if (genesetscope=="reprseq"){ write.table(spegeneinfo, file=nfoutspege[[ab]], sep='\t', quote=F, row.names=F, col.names=T, append=T) }
				write.table(spegeneinfoplus, file=file.path(diroutspegedetail, paste(bnoutspege[[ab]], cla, genesetscope, "details.tab", sep='_')), sep='\t', quote=F, row.names=F, col.names=T, append=F)
				write.table(spegallgoterms, file=file.path(diroutspegedetail, paste(bnoutspege[[ab]], cla, genesetscope, "goterms.tab", sep='_')), sep='\t', quote=F, row.names=F, col.names=T, append=F)
				write.table(spegallpathways, file=file.path(diroutspegedetail, paste(bnoutspege[[ab]], cla, genesetscope, "pathways.tab", sep='_')), sep='\t', quote=F, row.names=F, col.names=T, append=F)
			}
			dbExecute(dbcon, "DROP TABLE spegeneannots;")
			dbCommit(dbcon)
		}
	}
}
#~ print("Warnings:", quote=F)
#~ print(warnings(), quote=F)
print(sprintf("wrote ouput in file '%s'", nfoutspege), quote=F)
