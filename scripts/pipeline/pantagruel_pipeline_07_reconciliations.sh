#!/bin/bash

#########################################################
## PANTAGRUEL:                                         ##
##             a pipeline for                          ##
##             phylogenetic reconciliation             ##
##             of a bacterial pangenome                ##
#########################################################

# Copyright: Florent Lassalle (f.lassalle@imperial.ac.uk), 30 July 2018

if [ -z "$1" ] ; then echo "missing mandatory parameter: pantagruel config file" ; echo "Usage: $0 ptg_env_file" ; exit 1 ; fi
envsourcescript="$1"
source ${envsourcescript}

checkfoldersafe ${alerec}

###############################################
## 07. Gene tree / Species tree reconciliations
###############################################

### perform reconciliations with ALE

# parameters to be set: defaults:
#~ export ALEversion='v0.4'
#~ export ALEalgo='ALEml_undated'
#~ export recsamplesize=1000
#~ export ALEsourcenote='program compiled from source code from of https://github.com/ssolo/ALE/commits/63f0a3c964074a15f61fd45156ab9e10b5dd45ef'
if [ -z ${reccolid} ] ; then
 reccolid=1
fi
# derived parameters
if [ ${ALEalgo} == 'ALEml_undated' ] ; then
  export rectype='undat'
else
  export rectype='dated'
fi
export reccol="ale_${chaintype}_${rectype}_${reccolid}"
export recs=${alerec}/${chaintype}_recs

tasklist=${coltreechains}/${collapsecond}/${colmethod}_Gtrees_list
ls ${coltreechains}/${collapsecond}/${colmethod}/*-Gtrees.nwk > $tasklist
alelogs=${ptgdb}/logs/ALE
mkdir -p $alelogs/${reccol}
outrecdir=${recs}/${collapsecond}/${colmethod}/${reccol}
mkdir -p $outrecdir

# perform receonciliations sequentially (one gene family after another)
${ptgscripts}/ale_sequential.sh ${tasklist} ${outrecdir} Stree.nwk ${recsamplesize} ${ALEalgo}

export reccoldate=$(date +%Y-%m-%d)
echo -e "${reccolid}\t${reccoldate}" > ${genetrees}/reccol

### parse the inferred scenarios
# parameters to be set
if [ -z $parsedreccolid ] ; then
  parsedreccolid=1
fi
# derived parameters
export parsedreccol=${reccol}_parsed_${parsedreccolid}
export parsedrecs=${alerec}/parsed_recs/${parsedreccol}

mkdir -p ${parsedrecs}
reclist=$outrecdir/ale_collapsed_${rectype}_uml_rec_list
${ptgscripts}/lsfullpath.py "${outrecdir}/ale_collapsed_${rectype}/*ml_rec" > $reclist
 
## normalise the species tree branch labels across gene families
## and look for correlated transfer events across gene families
python ${ptgscripts}/parse_collapsedALE_scenarios.py --rec_sample_list ${reclist} \
 --populations ${speciestree/.full/}_populations --reftree ${speciestree}.lsd.newick \
 --dir_table_out ${parsedrecs} --evtype ${evtypeparse} --minfreq ${minevfreqparse} \
 --threads 8  &> $entlogs/parse_collapsedALE_scenarios.log &

export parsedreccoldate=$(date +%Y-%m-%d)
echo -e "${parsedreccolid}\t${parsedreccoldate}" > ${genetrees}/parsedreccol

## store reconciliation parameters and load parsed reconciliation data into database
${ptgscripts}/pantagruel_sqlitedb_phylogeny_populate_reconciliations.sh ${database} ${sqldb} ${parsedrecs} ${ALEversion} ${ALEalgo} ${ALEsourcenote} ${parsedreccol} ${parsedreccolid} ${parsedreccoldate}

# rapid survey of event density over the reference tree
for freqthresh in 0.1 0.25 0.5 ; do
sqlite3 ${sqldb} """
.mode tabs 
select don_branch_id, don_branch_name, rec_branch_id, rec_branch_name, event_type, nb_lineages, cum_freq, cum_freq/nb_lineages as avg_support from (
 select don_branch_id, don_stree.branch_name as don_branch_name, rec_branch_id, rec_stree.branch_name as rec_branch_name, event_type, count(*) as nb_lineages, sum(freq)::real/${nsample} as cum_freq
  from gene_lineage_events 
  inner join species_tree_events using (event_id) 
  inner join species_tree as rec_stree on rec_branch_id=rec_stree.branch_id
  left join species_tree as don_stree on don_branch_id=don_stree.branch_id
 where freq >= ( ${freqthresh} * ${recsamplesize} )
 group by don_branch_id, don_branch_name, rec_branch_name, rec_branch_id, event_type 
) as weg
order by nb_lineages desc, avg_support desc;
""" > ${parsedrecs}/summary_gene_tree_events_minfreq${freqthresh} 
wc -l ${parsedrecs}/summary_gene_tree_events_minfreq${freqthresh} 
${ptgscripts}/plot_spetree_event_density.r ${parsedrecs}/summary_gene_tree_events_minfreq${freqthresh} ${speciestree/.full/}_collapsedPopulations.nwk
done &

