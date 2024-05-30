#!/bin/bash

# author: Joanes Grandjean
# intial date: 05.05.2022
# last modified: 29.05.2024 (Jo)

# changelog
# 29.05.2024
# use the --inclusion_ids flag to run rabies one func at a time
# use the $TMPDIR environment variable to run rabies on /scratch and not on local project folder

#define what root dir you want to use, where the bids folder is, where the tmp scripts will go, and where the output will go
root_dir="/project/4180000.41/novo/mila_jo/"
bids=$root_dir"/bids_niftis_lowAnesSubset"
script_dir=$root_dir"/tmp_rabies_scripts"
output_dir=$root_dir"/output"

#define what version of rabies you want to use. run `ls /opt/rabies/` to see what versions are on
rabies="/opt/rabies/0.5.1/rabies.sif"

#arguments for RABIES preprocessing, confound regression, analysis. see https://rabies.readthedocs.io/ for more info
prep_arg='--commonspace_reg masking=false,brain_extraction=false,template_registration=SyN,fast_commonspace=true --TR 1' 
conf_arg='--highpass 0.01 --smoothing_filter 0.3 --lowpass 0.1 --conf_list mot_6 WM_signal CSF_signal vascular_signal --frame_censoring FD_censoring=true,FD_threshold=0.05,DVARS_censoring=true,minimum_timepoint=120 --read_datasink'
analysis_arg='--data_diagnosis --group_ica apply=true,dim=10,random_seed=1 --seed_list /project/4180000.41/novo/seed/seed_S1-right_mouse.nii.gz'

#make the script directory. this is where your runnable rabies script per func scan will be run. 
mkdir -p $script_dir
mkdir -p $output_dir
cd $script_dir

#this is the main loop. by default, it will loop over every func scan that you have in your bids directory and make a separate script for it. 
find $bids -name *_bold.nii.gz | while read line
do

#edit the func file name and path for rabies
##replace the full path to the bids directory with a relative path for rabies
func_file="${line//${bids}/}"
func_file="/bids"$func_file

##set the name of the script file that will be created. 
func_base=$(basename $func_file)
func_noext="$(remove_ext $func_base)"
script_file=$script_dir/$func_noext'.sh'

echo "now doing subject "$func_noext

#initialize the script with a bang and slurm header. you can edit the time and mem options if you think you need more or less resources. 
echo '#!/bin/bash' > $script_file
echo "#SBATCH --job-name="$func_noext >> $script_file
echo "#SBATCH --nodes=1" >> $script_file
echo "#SBATCH --time=12:00:00" >> $script_file
echo "#SBATCH --mail-type=FAIL" >> $script_file
echo "#SBATCH --partition=batch" >> $script_file
echo "#SBATCH --mem=16GB" >> $script_file

#create temporary folders in scratch folder so you don't clutter your project folder
echo "preprocess=$""TMPDIR/preprocess" >> $script_file
echo "confound=$""TMPDIR/confound" >> $script_file
echo "analysis=$""TMPDIR/analysis" >> $script_file

echo "mkdir -p $""preprocess" >> $script_file
echo "mkdir -p $""confound" >> $script_file
echo "mkdir -p $""analysis" >> $script_file 



#run the preprocessing step of rabies
echo "apptainer run -B "${bids}":/bids:ro -B $""{preprocess}:/preprocess -B $""{confound}:/confound -B $""{analysis}:/analysis "${rabies}" --inclusion_ids "${func_file}" -p MultiProc preprocess /bids /preprocess "${prep_arg} >> $script_file 

#copy the QC report
echo "cp -r $""{preprocess}/preprocess_QC_report "$output_dir >> $script_file 

#run the confound correction step of rabies
echo "apptainer run -B "${bids}":/bids:ro -B $""{preprocess}:/preprocess -B $""{confound}:/confound -B $""{analysis}:/analysis "${rabies}" --inclusion_ids "${func_file}" -p MultiProc confound_correction /preprocess /confound "${conf_arg} >> $script_file 

#run the analysis step of rabies
echo "apptainer run -B "${bids}":/bids:ro -B $""{preprocess}:/preprocess -B $""{confound}:/confound -B $""{analysis}:/analysis "${rabies}" --inclusion_ids "${func_file}" -p MultiProc analysis /confound /analysis "${analysis_arg} >> $script_file 

#copy the analysis outputs and the data diagnosis to the output directory
echo "mv $""analysis/data_diagnosis_datasink/group_melodic.ica $""analysis/data_diagnosis_datasink/ICA_"$func_noext >> $script_file 
echo "cp -r $""analysis/analysis_datasink "$output_dir >> $script_file 
echo "cp -r $""analysis/data_diagnosis_datasink "$output_dir >> $script_file 


#clean up scratch
echo "rm -rf $""preprocess" >> $script_file 
echo "rm -rf $""confound" >> $script_file 
echo "rm -rf $""analysis" >> $script_file 

#uncomment one of the following if you want to run the scripts automatically (do so if you are confident it will work)
##this is if you are using the new slurm system
sbatch $script_file

##this is if you are using the old pbs system
#qsub -l 'nodes=1,mem=16mb,walltime=12:00:00' $script_file 

#end of the loop
done
