#!/bin/csh
#                       run.csh
#                      ---------
#   Run src/run.x (timestepping for src/run.x).
#   Run parameters are set in run.in.
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

# Set up PATH for people who don't include $PENCIL_HOME/bin by default
if ($?PENCIL_HOME) setenv PATH ${PATH}:${PENCIL_HOME}/bin

# Prevent code from running twice (and removing files by accident)
if (-e "LOCK") then
  echo ""
  echo "run.csh: found LOCK file"
  echo "This may indicate that the code is currently running in this directory"
  echo "If this is a mistake (eg after a crash), remove the LOCK file by hand:"
  echo "rm LOCK"
  exit
endif
if (! -e "NEVERLOCK") touch LOCK

# Determine whether this is MPI, how many CPUS etc.
source getconf.csh

#
#  On Horseshoe, distribute var.dat from the server to the various nodes
#
if ($local_disc) then
  set nodelist = `cat $PBS_NODEFILE`
  set i=0
  foreach node ($nodelist)
    $SCP $datadir/proc$i/var.dat ${node}:$SCRATCH_DIR
    set i=`expr $i + 1`
    echo 'i=' $i
  end
endif

# Clean up control and data files
rm -f STOP RELOAD fort.20

# On Horseshoe cluster, initialize automatic copying
# of snapshots back to the data directory
# Also, copy executable to $SCRATCH_DIR of master node
# and start top command on all procs
if ($local_disc) then
  echo "Use local scratch disk"
  copy-snapshots -v >& copy-snapshots.log &
echo "ls check beforehand src/run.x $SCRATCH_DIR"
ls -lt src/run.x $SCRATCH_DIR
  cp src/run.x $SCRATCH_DIR
echo "ls check afterwards src/run.x $SCRATCH_DIR"
ls -lt src/run.x $SCRATCH_DIR
  remote-top >& remote-top.log &
endif

# Run run.x
date
echo "$mpirun $mpirunops $npops $run_x $x_ops"
echo $mpirun $mpirunops $npops $run_x $x_ops >! run_command.log
time $mpirun $mpirunops $npops $run_x $x_ops
date

# On Horseshoe cluster, copy var.dat back to the data directory
if ($local_disc) then
  echo "Use local scratch disk"
  copy-snapshots -v var.dat
  echo "done, will now killall copy-snapshots"
  killall copy-snapshots
endif

# Shut down lam if we have started it
if ($booted_lam) lamhalt

# remove LOCK file
if (-e "LOCK") rm -f LOCK

# cut & paste for job submission on the mhd machine
# bsub -n  4 -q 4cpu12h -o run.`timestr` -e run.`timestr` run.csh
# bsub -n  8 -q 8cpu12h mpijob dmpirun src/run.x
# bsub -n 16 -q 16cpu8h mpijob dmpirun src/run.x
# bsub -n  8 -q 8cpu12h -o run.log -w 'exit(123456)' mpijob dmpirun src/run.x

# qsub -l ncpus=64,mem=32gb,walltime=500:00:00 -W group_list=UK07001 -q UK07001 run.csh
# qsub -l nodes=4:ppn=1,mem=500mb,cput=24:00:00 -q p-long run.csh
# qsub -l ncpus=16,mem=1gb,cput=400:00:00 -q parallel run.csh
# qsub -l nodes=128,walltime=10:00:00 -q workq run.csh
# eval `env-setup lam`; qsub -v PATH -pe lam 8 -j y -o run.log run.csh








