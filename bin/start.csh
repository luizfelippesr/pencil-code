#!/bin/csh
# CVS: $Id: start.csh,v 1.55 2004-06-03 17:25:53 brandenb Exp $

#                       start.csh
#                      -----------
#   Run src/start.x (initialising f for src/run.x).
#   Start parameters are set in start.in.
#
# Run this script with csh:
#PBS -S /bin/csh
#$ -S /bin/csh
#@$-s /bin/csh
#
# Join stderr and stout:
#$ -j y -o run.log
#@$-eo
#
# Work in submit directory (SGE):
#$ -cwd

# Work in submit directory (PBS):
if ($?PBS_O_WORKDIR) then
  cd $PBS_O_WORKDIR
endif

# Work in submit directory (SUPER-UX's nqs):
if ($?QSUB_WORKDIR) then
  cd $QSUB_WORKDIR
endif

# Common setup for start.csh, run.csh, start_run.csh:
# Determine whether this is MPI, how many CPUS etc.
source getconf.csh

#
#  If we don't have a data subdirectory: stop here (it is too easy to
#  continue with an NFS directory until you fill everything up).
#
if (! -d "$datadir") then
  echo ""
  echo ">>  STOPPING: need $datadir directory"
  echo ">>  Recommended: create $datadir as link to directory on a fast scratch"
  echo ">>  Not recommended: you can generate $datadir with 'mkdir $datadir', "
  echo ">>  but that will most likely end up on your NFS file system and be"
  echo ">>  slow"
  echo
  exit 0
endif

# ---------------------------------------------------------------------- #
#  for testing backwards compatibility, it is useful to make sure
#  start.x is never excecuted, and that the old var.dat etc files
#  are not deleted. time_series.dat will be renamed, so we can write
#  a fresh one to compare against.
#
if (-e NOSTART) then
  echo "The file NOSTART exists, so we have to exit"
  echo "and don't overwrite existing data"
  mv $datadir/time_series.dat $datadir/time_series.`timestr`
  exit
endif

# ---------------------------------------------------------------------- #

# Create list of subdirectories
# If the file NOERASE exists, the old directories are not erased
#   (start.x also knows then that var.dat is not created)
foreach dir ($procdirs $subdirs)
  # Make sure a sufficient number of subdirectories exist
  set ddir = "$datadir/$dir"
  if (! -e $ddir) then
    mkdir $ddir
  else
    # Clean up
    # when used with lnowrite=T, for example, we don't want to remove var.dat:
    set list = \
        `/bin/ls $ddir/VAR* $ddir/TAVG* $ddir/*.dat $ddir/*.info $ddir/slice*`
    if (! -e NOERASE) then
      foreach rmfile ($list)
        if ($rmfile != $ddir/var.dat) rm -f $rmfile >& /dev/null
      end
    endif
  endif
end

# Clean up previous runs
if (! -e NOERASE) then
  if (-e $datadir/time_series.dat && ! -z $datadir/time_series.dat) \
      mv $datadir/time_series.dat $datadir/time_series.`timestr`
  rm -f $datadir/*.dat $datadir/*.nml $datadir/param*.pro $datadir/index*.pro \
        $datadir/averages/* >& /dev/null
endif

# If local disk is used, copy executable to $SCRATCH_DIR of master node
if ($local_binary) then
  echo "Copying start.x to $SCRATCH_DIR"
  cp src/start.x $SCRATCH_DIR
  remote-top >& remote-top.log &
endif

# Run start.x
date
echo "$mpirun $mpirunops $npops $start_x $x_ops"
time $mpirun $mpirunops $npops $start_x $x_ops
set start_status=$status	# save for exit
echo ""
date

# If local disk is used, copy var.dat back to the data directory
if ($local_disc) then
  echo "Copying var.dat back to data directory"
  copy-snapshots -v var.dat
  copy-snapshots -v timeavg.dat
  copy-snapshots -v dxyz.dat

  if ($remove_scratch_root) then
    rm -rf $SCRATCH_DIR
  endif
endif

exit $start_status		# propagate status of mpirun

# cut & paste for job submission on the mhd machine
# bsub -n  4 -q 4cpu12h mpijob dmpirun src/start.x
# bsub -n  8 -q 8cpu12h mpijob dmpirun src/start.x
# bsub -n 16 -q 16cpu8h mpijob dmpirun src/start.x

# cut & paste for job submission for PBS
# qsub -l ncpus=64,mem=32gb,walltime=1:00:00 -W group_list=UK07001 -q UK07001 start.csh
# qsub -l nodes=4:ppn=1,mem=500mb,cput=24:00:00 -q p-long start.csh
# qsub -l ncpus=4,mem=1gb,cput=100:00:00 -q parallel start.csh
# qsub -l nodes=128,mem=64gb,walltime=1:00:00 -q workq start.csh
