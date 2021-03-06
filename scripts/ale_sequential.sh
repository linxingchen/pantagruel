#!/bin/bash

tasklist=${1}
resultdir=${2}
spetree=${3}
nrecs=${4}
alealgo=${5}

echo "ale_sequential.sh call was: ${@}"
echo "with variables set as: tasklist=${tasklist}, resultdir=${resultdir}, spetree=${spetree}, nrecs=${nrecs}, alealgo=${alealgo}"

usage() {
	echo "Usage: ale_sequential.sh tasklist resultdir spetree [nrecs; default=1000] [alealgo; default='ALEml_undated']"
}

## verify key variable definition
# tasklist
echo "tasklist:"
if [ -z $tasklist ] ; then
  echo "ERROR: need to define variable tasklist ; exit now"
  usage
  exit 2
else
  ls $tasklist
  if [ $? != 0 ] ; then
    echo "ERROR: file '$tasklist' is missing ; exit now"
  usage
    exit 2
  fi
fi

# resultdir
echo "resultdir:"
if [ -z $resultdir ] ; then
  echo "ERROR: need to define variable resultdir ; exit now"
  usage
  exit 2
else
  ls $resultdir -d
  if [ $? != 0 ] ; then
    echo "directory '$resultdir' is missing ; create it now"
    mkdir -p $resultdir
    if [ $? != 0 ] ; then
      echo "could not create directory '$resultdir' ; exit now"
      exit 2
    fi
  fi
fi
# spetree
echo "spetree:"
if [ -z $spetree ] ; then
  echo "ERROR: need to define variable spetree ; exit now"
  usage
  exit 2
else
  ls $spetree
  if [ $? != 0 ] ; then
    echo "look for $spetree species tree file in $dnchain/ folder"
    ls ${dnchain}/${nfrad}*${spetree}*
    if [ $? != 0 ] ; then
      echo "ERROR: file '$spetree' is missing ; exit now"
      exit 2
    else
      echo "found it!" 
      spetree=(`ls ${dnchain}/${nfrad}*${spetree}*`)
      echo "will use spetree=${spetree[0]}"
    fi
  fi
fi
# nrecs
echo "nrecs:"
if [ -z $nrecs ] ; then
  echo -n "Default: "
  nrecs=1000
fi
echo "will sample $nrecs reconciliations"
# alealgo
echo "alealgo:"
if [ -z $alealgo ] ; then
  echo -n "Default: "
  alealgo='ALEml_undated'
fi
echo "will use $alealgo algorithm for reconciliation estimation"
# relburninfrac
echo "relburninfrac:"
if [ -z $relburninfrac ] ; then
  echo -n "Default: "
  relburninfrac=0.25
fi
echo "will discard $relburninfrac fraction of the tree chain as burn-in"
  
alebin=$HOME/software/ALE/build/bin
# watchmem
echo "# watchmem:"
if [ -z $watchmem ] ; then
  aleexe="${alebin}/${alealgo}"
else
  if [[ "$watchmem"=="y" || "$watchmem"=="yes" || "$watchmem"=="true" ]] ; then
    memusg="/apps/memusage/memusage"
  else
    memusg="$watchmem"
  fi
  aleexe="${memusg} ${alebin}/${alealgo}"
  echo "will watch memory usage with '${memusg}'"
fi
# worklocal
echo "# worklocal:"
if [ -z $worklocal ] ; then
  echo "(Use default)"
  worklocal="yes"
else
  if [[ "$worklocal"=="n" || "$worklocal"=="false" ]] ; then
    worklocal="no"
  elif [[ "$worklocal"=="y" || "$worklocal"=="true" ]] ; then
    worklocal="yes"
  fi
fi
echo "will work (read/write) locally: ${worklocal}"
echo ""
echo "# # # #"
echo ""



for nfchain in $(cat $tasklist) ; do
  echo "current task"
  echo $nfchain
  python << EOF
  with open('$nfchain', 'r') as fchain:
    chainone = fchain.readline()
    print 'ntaxa:', chainone.count('(') + 2

EOF
  echo ""
  echo "# # # #"
  dnchain=`dirname $nfchain`
  bnchain=`basename $nfchain`
  nfrad=${bnchain%%-*}


  ####
  if [[ "$worklocal"=="yes" ]] ; then
    # copy input files locally
    rsync -az ${nfchain} ./
    ls -lh ${bnchain}
    if [ $? != 0 ] ; then
    echo "ERROR: could not copy input file ${bnchain} locally; exit now"
    exit 2
    else
    chain="./${bnchain}"
    fi
  else
    chain=${nfchain}
  fi


  # resume from run with already estimated parameters,
  # to perform further reconciliation sampling
  # (also allows to sample from defined parameter set)
  if [ ${#DTLrates[@]} -eq 3 ] ; then
    echo -e "will perform analysis with set DTL rate parameters:\n${DTLrates[@]}"
  elif [ ! -z $resumealefromtag ] ; then
    estparam=($(ls ${resultdir}/${bnchain}.ale.*ml_rec${resumealefromtag}))
    if [ ! -z ${estparam} ] ; then
    DTLrates=($(grep -A 1 "rate of" ${estparam} | grep 'ML' | awk '{print $2,$3,$4}'))
    if [ ${#DTLrates[@]} -eq 3 ] ; then
      echo -e "will resume analysis from previously estimated DTL rate parameters:\n${DTLrates[@]} \nas found in file:\n'$estparam'"
      prevcomputetime=$(cat ${resultdir}/${nfrad}.ale.computetime${resumealefromtag} | cut -f3)
      if [ ! -z $prevcomputetime ] ; then
      echo -e "will add previous computation time spent estimating parameters found in file:\n'${dnchain}/${nfrad}.ale.computetime${resumealefromtag}'\nto new record:\n'./${nfrad}.ale.computetime'"
      fi
    fi
    fi
  fi
  echo ""

  if [[ -e $nfchain.ale ]] ; then
    if [[ "$worklocal"=="yes" ]] ; then
     # copy input files locally
     rsync -az ${nfchain}.ale ./
    fi
    echo "use pre-existing ALE index file:"
    ls $nfchain.ale
  elif [[ -e ${resultdir}/${bnchain}.ale ]] ; then
    if [[ "$worklocal"=="yes" ]] ; then
     # copy input files locally
     rsync -az ${resultdir}/${bnchain}.ale ./
    fi
    echo "use pre-existing ALE index file:"
    ls -lh ${chain}.ale
  else
    # prepare ALE index
    lenchain=`wc -l ${chain} | cut -d' ' -f1`
    burnin=`echo "$lenchain * $relburninfrac" | bc`
    echo "input tree chain is ${lenchain} long; burnin is set to ${burnin%%.*}"
    echo "# ${alebin}/ALEobserve ${chain} burnin=${burnin%%.*}"
    ${alebin}/ALEobserve ${chain} burnin=${burnin%%.*}
  fi
  date

  # start timing in seconds
  SECONDS=0
  # run ALE reconciliation 
  if [ "$alealgo" == 'ALEml' ] ; then
    alecmd="${aleexe} ${spetree} ${chain}.ale ${nrecs} _"
    if [ ${#DTLrates[@]} -eq 3 ] ; then alecmd="${alecmd} ${DTLrates[@]}" ; fi
  elif [ "$alealgo" == 'ALEml_undated' ] ; then
    alecmd="${aleexe} ${spetree} ${chain}.ale sample=${nrecs} separators=_"
    if [ ${#DTLrates[@]} -eq 3 ] ; then alecmd="${alecmd} delta=${DTLrates[0]} tau=${DTLrates[0]} lambda=${DTLrates[0]}" ; fi
  else
    echo "ALE algorithm $alealgo not supported in this script, sorry; exit now"
    exit 2
  fi
  echo "# ${alecmd}"
  ${alecmd}
    
  echo ""
  echo "# # # #"

  ALETIME=$SECONDS
  if [ ! -z $prevcomputetime ] ; then ALETIME=$(( $ALETIME + $prevcomputetime )) ; fi
  echo -e "$nfrad\t$alealgo\t$ALETIME" > $nfrad.ale.computetime
  echo "reconciliation estimation took" $(date -u -d @${ALETIME} +"%Hh%Mm%Ss") "total time"
  if [ ! -z $prevcomputetime ] ; then echo "(including ${prevcomputetime} in previous run)" ; fi

  echo "# ls"
  ls

  # save files
  if [[ "$worklocal"=="yes" ]] ; then
    # will rapartiate files ot output dir
    savecmd="rsync -az"
  else
    savecmd="mv -f"
  fi
  ls ./${nfrad}*.ale.* > /dev/null
  if [ $? == 0 ] ; then
    savecmd1="$savecmd ./${nfrad}*.ale* $resultdir/"
    echo "# $savecmd1"
    $savecmd1
    if [ $? != 0 ] ; then
    echo "ERROR: unable to save result files from $PWD/ to $resultdir/"
    fi
  else
  ls ${dnchain}/${nfrad}*.ale.* > /dev/null
  if [ $? == 0 ] ; then
    savecmd2="$savecmd ${dnchain}/${nfrad}*.ale.* $resultdir/"
    echo "# $savecmd2"
    $savecmd2
    if [ $? != 0 ] ; then
    echo "ERROR: unable to save result files from $dnchain to $resultdir/"
    fi
  else
    echo "ERROR: unable to find the result files"
  fi
  fi

done
