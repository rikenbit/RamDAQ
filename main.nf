#!/usr/bin/env nextflow
/*
========================================================================================
                         ramdaq
========================================================================================
 ramdaq Analysis Pipeline.
 #### Homepage / Documentation
 https://github.com/rikenbit/ramdaq
----------------------------------------------------------------------------------------
*/

def helpMessage() {
    log.info nfcoreHeader()
    log.info"""

    Usage:

    The typical command for running the pipeline is as follows:

    nextflow run rikenbit/ramdaq --reads '*_R{1,2}.fastq.gz' -profile docker

    Pipeline setting:
      -profile [str]                  Configuration profile to use. Can use multiple (comma separated)
                                      Available: docker, singularity, test, and more
      -c                              Specify the path to a specific config file
      --reads [file]                  Path to input data (must be surrounded with quotes)
      --single_end                    Specifies that the input is single-end reads
      --stranded [str]                unstranded : default
                                      fr-firststrand : First read corresponds to the reverse complemented counterpart of a transcript
                                      fr-secondstrand : First read corresponds to a transcript
      --genome [str]                  Name of human or mouse latest reference: ${params.genomes.keySet().join(", ")}
      --saveReference                 Save the generated reference files to the results directory
      --local_annot_dir [str]         Base path for local annotation files
      --entire_max_cpus [N]            Maximum number of CPUs to use for each step of the pipeline. Should be in form e.g. --entire_max_cpus 16. Default: '${params.entire_max_cpus}'
      --entire_max_memory [str]        Memory limit for each step of pipeline. Should be in form e.g. --entire_max_memory '16.GB'. Default: '${params.entire_max_memory}'  
        
    Other:
      --outdir [str]                  The output directory where the results will be saved
      -name [str]                     Name for the pipeline run. If not specified, Nextflow will automatically generate a random mnemonic
      -resume                         Specify this when restarting a pipeline
      --max_memory [str]              Memory limit for each step of pipeline. Should be in form e.g. --max_memory '8.GB'. Default: '${params.max_memory}'
      --max_time [str]                Time limit for each step of the pipeline. Should be in form e.g. --max_time '2.h'. Default: '${params.max_time}'
      --max_cpus [str]                Maximum number of CPUs to use for each step of the pipeline. Should be in form e.g. --max_cpus 1. Default: '${params.max_cpus}'
      --monochrome_logs               Set to disable colourful command line output and live life in monochrome

    Fastqmcf:
      --maxReadLength [N]             Maximum remaining sequence length (Default: 75)
      --minReadLength [N]             Minimum remaining sequence length (Default: 36)
      --skew [N]                      Skew percentage-less-than causing cycle removal (Default: 4)
      --quality [N]                   Quality threshold causing base removal (Default: 30)
    
    Hisat2:
      --softclipping                  HISAT2 allow soft-clip reads near their 5' and 3' ends (Default: disallow)
      --hs_threads_num [N]            HISAT2 to launch a specified number of parallel search threads (Default: 1)
    
    RSEM:
      --rsem_threads_num [N]          Number of threads to use (Default: 1)
    
    FeatureCounts:
      --extra_attributes              Define which extra parameters should also be included in featureCounts (Default: 'gene_name')
      --group_features                Define the attribute type used to group features (Default: 'gene_id')
      --count_type                    Define the type used to assign reads (Default: 'exon')
      --allow_multimap                Multi-mapping reads/fragments will be counted (Default: true)
      --allow_overlap                 Reads will be allowed to be assigned to more than one matched meta-feature (Default: true)
      --count_fractionally            Assign fractional counts to features  (Default: true / This option must be used together with ‘--allow_multimap’ or ‘--allow_overlap’ or both)
      --fc_threads_num [N]            Number of the threads (Default: 1)
      --group_features_type           Define the type attribute used to group features based on the group attribute (default: 'gene_type')
    
    For ERCC RNA Spike-In Controls:
      --spike_in_ercc [str]           Dilution rate of the ERCC Spike-In Control Mix 1. Use when the samples contain the ERCC Spike-In Control Mix 1. The value is used to calculate copy number of ERCC. If the value is not specified, '2e-7' is used as dilution rate. (default: false)
      --spike_in_sirv [str]           Dilution rate of the SIRV-Set 4. Use when the samples contain the SIRV-Set 4. The value is used to calculate copy number of ERCC in the SIRV-Set 4. (default: false)
    
    MultiQC report:
      --sampleLevel                   Used to turn off the edgeR MDS and heatmap. Set automatically when running on fewer than 3 samples

    """.stripIndent()
}

// Show help message
if (params.help) {
    helpMessage()
    exit 0
}

///////////////////////////////////////////////////////////////////////////////
/*
* SET UP CONFIGURATION VARIABLES
*/
///////////////////////////////////////////////////////////////////////////////

// Check if genome exists in the config file
if (params.genomes && params.genome && !params.genomes.containsKey(params.genome)) {
    exit 1, "The provided genome '${params.genome}' is not available. Currently the available genomes are ${params.genomes.keySet().join(", ")}"
}

// Configurable variables
params.adapter = params.genome ? params.genomes[ params.genome ].adapter ?: false : false
params.hisat2_idx = params.genome ? params.genomes[ params.genome ].hisat2_idx ?: false : false
params.chrsize = params.genome ? params.genomes[ params.genome ].chrsize ?: false : false
params.bed = params.genome ? params.genomes[ params.genome ].bed ?: false : false
params.gtf = params.genome ? params.genomes[ params.genome ].gtf ?: false : false
params.mt_gtf = params.genome ? params.genomes[ params.genome ].mt_gtf ?: false : false
params.rrna_gtf = params.genome ? params.genomes[ params.genome ].rrna_gtf ?: false : false
params.histone_gtf = params.genome ? params.genomes[ params.genome ].histone_gtf ?: false : false
params.hisat2_sirv_idx = params.genome ? params.genomes[ params.genome ].hisat2_sirv_idx ?: false : false
params.rsem_sirv_idx = params.genome ? params.genomes[ params.genome ].rsem_sirv_idx ?: false : false
params.rsem_allgene_idx = params.genome ? params.genomes[ params.genome ].rsem_allgene_idx ?: false : false

// Validate inputs
if (params.stranded && params.stranded != 'unstranded' && params.stranded != 'fr-firststrand' && params.stranded != 'fr-secondstrand') {
    exit 1, "Invalid stranded option: ${params.stranded}. Valid options: 'unstranded' or 'fr-firststrand' or 'fr-secondstrand'!"
}

if (params.adapter) { ch_adapter = file(params.adapter, checkIfExists: true) } else { exit 1, "Adapter file not found: ${params.adapter}" }

if (params.spike_in_ercc && params.spike_in_ercc.toString() == 'true') { ch_spike_in_ercc = params.spike_in_ercc_default_amount } else { ch_spike_in_ercc = params.spike_in_ercc }
if (params.spike_in_sirv && params.spike_in_sirv.toString() == 'true') { exit 1, "--spike_in_sirv option requires a dilution rate value" }
if (params.spike_in_sirv) { ch_spike_in_ercc = params.spike_in_sirv }

if (params.hisat2_idx) {
    if (params.hisat2_idx.endsWith('.tar.gz')) {
        file(params.hisat2_idx, checkIfExists: true)

        process untar_hisat2_idx {
            label 'process_low'
            publishDir path: { params.saveReference ? "${params.outdir}/reference_genome/hisat2" : params.outdir },
               saveAs: { params.saveReference ? it : null }, mode: 'copy'

            input:
            path gz from params.hisat2_idx

            output:
            file "$untar/*.ht2" into ch_hisat2_idx

            script:
            untar = gz.toString() - '.tar.gz'
            """
            tar -xvf $gz
            """
        }
        
    } else {
        ch_hisat2_idx = Channel
        .from(params.hisat2_idx)
        .flatMap{file(params.hisat2_idx, checkIfExists: true)}
        .ifEmpty { exit 1, "HISAT2 index files not found: ${params.hisat2_idx}" }
        
        //ch_hisat2_idx = file(params.hisat2_idx, checkIfExists: true)
    }
}

if (params.spike_in_sirv) {

    if (params.hisat2_sirv_idx) {
        if (params.hisat2_sirv_idx.endsWith('.tar.gz')) {
            file(params.hisat2_sirv_idx, checkIfExists: true)

            process untar_hisat2_sirv_idx {
                label 'process_low'
                publishDir path: { params.saveReference ? "${params.outdir}/reference_genome/sirv" : params.outdir },
                   saveAs: { params.saveReference ? it : null }, mode: 'copy'

                input:
                path gz from params.hisat2_sirv_idx

                output:
                file "$untar/*.ht2" into ch_hisat2_sirv_idx

                script:
                untar = gz.toString() - '.tar.gz'
                """
                tar -xvf $gz
                """
            }
        } else {
            ch_hisat2_sirv_idx = Channel
            .from(params.hisat2_sirv_idx)
            .flatMap{file(params.hisat2_sirv_idx, checkIfExists: true)}
            .ifEmpty { exit 1, "HISAT2 SIRVome index files not found: ${params.hisat2_sirv_idx}" }
        }
    } else { exit 1, "HISAT2 SIRVome index files not found: ${params.hisat2_sirv_idx}" } 

    if (params.rsem_sirv_idx) {
        if (params.rsem_sirv_idx.endsWith('.tar.gz')) {
            file(params.rsem_sirv_idx, checkIfExists: true)

            process untar_rsem_sirv_idx {
                label 'process_low'
                publishDir path: { params.saveReference ? "${params.outdir}/reference_genome/sirv" : params.outdir },
                   saveAs: { params.saveReference ? it : null }, mode: 'copy'

                input:
                path gz from params.rsem_sirv_idx

                output:
                file "$untar/*" into ch_rsem_sirv_idx

                script:
                untar = gz.toString() - '.tar.gz'
                """
                tar -xvf $gz
                """
            }
        } else {
            ch_rsem_sirv_idx = Channel
            .from(params.rsem_sirv_idx)
            .flatMap{file(params.rsem_sirv_idx, checkIfExists: true)}
            .ifEmpty { exit 1, "RSEM SIRVome index files not found: ${params.rsem_sirv_idx}" }
        }
    } else { exit 1, "RSEM SIRVome index files not found: ${params.rsem_sirv_idx}" } 
} else {
    ch_hisat2_sirv_idx = false
    ch_rsem_sirv_idx = false
}

if (params.rsem_allgene_idx) {
    if (params.rsem_allgene_idx.endsWith('.tar.gz')) {
        file(params.rsem_allgene_idx, checkIfExists: true)
        
        process untar_rsem_allgene_idx {
            label 'process_low'
            publishDir path: { params.saveReference ? "${params.outdir}/reference_genome/sirv" : params.outdir },
               saveAs: { params.saveReference ? it : null }, mode: 'copy'
            input:
            path gz from params.rsem_allgene_idx
            output:
            file "$untar/*" into ch_rsem_allgene_idx
            script:
            untar = gz.toString() - '.tar.gz'
            """
            tar -xvf $gz
            """
        }
    } else {
        ch_rsem_allgene_idx = Channel
        .from(params.rsem_allgene_idx)
        .flatMap{file(params.rsem_allgene_idx, checkIfExists: true)}
        .ifEmpty { exit 1, "RSEM All genes index files not found: ${params.rsem_allgene_idx}" }
    }
} else { exit 1, "RSEM All genes index files not found: ${params.rsem_allgene_idx}" } 

if (params.chrsize) { ch_chrsize= file(params.chrsize, checkIfExists: true) } else { exit 1, "Chromosome sizes file not found: ${params.chrsize}" }
if (params.bed) { ch_bed= file(params.bed, checkIfExists: true) } else { exit 1, "BED file not found: ${params.bed}" }
if (params.gtf) { ch_gtf= file(params.gtf, checkIfExists: true) } else { exit 1, "GTF annotation file not found: ${params.gtf}" }
if (params.mt_gtf) { ch_mt_gtf= file(params.mt_gtf, checkIfExists: true) } else { exit 1, "Mitocondria GTF annotation file not found: ${params.mt_gtf}" }
if (params.rrna_gtf) { ch_rrna_gtf= file(params.rrna_gtf, checkIfExists: true) } else { exit 1, "rRNA GTF annotation file not found: ${params.rrna_gtf}" }
if (params.histone_gtf) { ch_histone_gtf= file(params.histone_gtf, checkIfExists: true) } else { exit 1, "Histone GTF annotation file not found: ${params.histone_gtf}" }

// Has the run name been specified by the user?
//  this has the bonus effect of catching both -name and --name
custom_runName = params.name
if (!(workflow.runName ==~ /[a-z]+_[a-z]+/)) {
    custom_runName = workflow.runName
}

// Stage config files
ch_multiqc_config = file("$baseDir/assets/multiqc_config.yaml", checkIfExists: true)
ch_multiqc_custom_config = params.multiqc_config ? Channel.fromPath(params.multiqc_config, checkIfExists: true) : Channel.empty()
ch_output_docs = file("$baseDir/docs/output.md", checkIfExists: true)

// Tools dir
ch_tools_dir = workflow.scriptFile.parent + "/tools"
ch_tools_dir_sirv = workflow.scriptFile.parent + "/tools"

ch_mdsplot_header = Channel.fromPath("$baseDir/assets/mdsplot_header.txt", checkIfExists: true)
ch_heatmap_header = Channel.fromPath("$baseDir/assets/heatmap_header.txt", checkIfExists: true)
ch_biotypes_header = Channel.fromPath("$baseDir/assets/biotypes_header.txt", checkIfExists: true)
ch_ercc_data = params.spike_in_sirv ? Channel.fromPath("$baseDir/assets/ercc_in_sirv_dataset.txt", checkIfExists: true) : Channel.fromPath("$baseDir/assets/ercc_dataset.txt", checkIfExists: true)
ch_ercc_corr_header = Channel.fromPath("$baseDir/assets/ercc_correlation_header.txt", checkIfExists: true)
ch_assignedgenome_header = Channel.fromPath("$baseDir/assets/barplot_assignedgenome_rate_header.txt", checkIfExists: true)
ch_num_of_detgene_header = Channel.fromPath("$baseDir/assets/barplot_num_of_detgene_header.txt", checkIfExists: true)
ch_fcounts_allgene_header = Channel.fromPath("$baseDir/assets/barplot_fcounts_allgene_header.txt", checkIfExists: true)
ch_fcounts_mt_header = Channel.fromPath("$baseDir/assets/barplot_fcounts_mt_header.txt", checkIfExists: true)
ch_fcounts_rrna_header = Channel.fromPath("$baseDir/assets/barplot_fcounts_rrna_header.txt", checkIfExists: true)
ch_fcounts_histone_header = Channel.fromPath("$baseDir/assets/barplot_fcounts_histone_header.txt", checkIfExists: true)
ch_pcaplot_header = Channel.fromPath("$baseDir/assets/pcaplot_header.txt", checkIfExists: true)
ch_tsneplot_header = Channel.fromPath("$baseDir/assets/tsneplot_header.txt", checkIfExists: true)
ch_umapplot_header = Channel.fromPath("$baseDir/assets/umapplot_header.txt", checkIfExists: true)

ch_num_of_gene_rsem_header = Channel.fromPath("$baseDir/assets/barplot_num_of_gene_rsem_header.txt", checkIfExists: true)
ch_num_of_ts_rsem_header = Channel.fromPath("$baseDir/assets/barplot_num_of_ts_rsem_header.txt", checkIfExists: true)

///////////////////////////////////////////////////////////////////////////////
/*
* Create a channel for input read files
*/
///////////////////////////////////////////////////////////////////////////////

if (params.readPaths) {
    if (params.single_end) {
        Channel
            .from(params.readPaths)
            .map { row -> [ row[0], [ file(row[1][0], checkIfExists: true) ] ] }
            .ifEmpty { exit 1, "params.readPaths was empty - no input files supplied" }
            .into { ch_read_files_fastqc; 
                    ch_read_files_fastqmcf }
    } else {
        Channel
            .from(params.readPaths)
            .map { row -> [ row[0], [ file(row[1][0], checkIfExists: true), file(row[1][1], checkIfExists: true) ] ] }
            .ifEmpty { exit 1, "params.readPaths was empty - no input files supplied" }
            .into { ch_read_files_fastqc; 
                    ch_read_files_fastqmcf }
    }
} else {
    Channel
        .fromFilePairs(params.reads, size: params.single_end ? 1 : 2)
        .ifEmpty { exit 1, "Cannot find any reads matching: ${params.reads}\nNB: Path needs to be enclosed in quotes!\nIf this is single-end data, please specify --single_end on the command line." }
        .into { ch_read_files_fastqc; 
                ch_read_files_fastqmcf;
                ch_debug }
}

// Header log info
log.info nfcoreHeader()
def summary = [:]
if (workflow.revision) summary['Pipeline Release'] = workflow.revision
summary['Run Name']         = custom_runName ?: workflow.runName
summary['Reads']            = params.reads
//summary['Fasta Ref']        = params.fasta
summary['Data Type']        = params.single_end ? 'Single-End' : 'Paired-End'
if (params.stranded)  {
    if (params.stranded == 'unstranded') summary['Strandness'] = 'Unstranded'
    if (params.stranded == 'fr-firststrand') summary['Strandness'] = 'Forward stranded'
    if (params.stranded == 'fr-secondstrand') summary['Strandness'] = 'Reverse stranded'
} else {
    summary['Strandness'] = 'Unstranded'
}
summary['Save Reference']   = params.saveReference ? 'Yes' : 'No'
if (params.hisat2_idx) summary['HISAT2 Index'] = params.hisat2_idx
if (params.hisat2_sirv_idx) summary['HISAT2 SIRVome Index'] = params.hisat2_sirv_idx
if (params.rsem_sirv_idx) summary['RSEM-Bowtie2 SIRVome Index'] = params.rsem_sirv_idx
if (params.rsem_allgene_idx) summary['RSEM-Bowtie2 All genes Index'] = params.rsem_allgene_idx
if (params.chrsize)  summary['Chromosome sizes'] = params.chrsize
if (params.bed) summary['BED Annotation'] = params.bed
if (params.gtf) summary['GTF Annotation'] = params.gtf
if (params.mt_gtf) summary['Mitocondria GTF Annotation'] = params.mt_gtf
if (params.rrna_gtf) summary['rRNA GTF Annotation'] = params.rrna_gtf
if (params.histone_gtf) summary['Histone GTF Annotation'] = params.histone_gtf
if (params.allow_multimap) summary['Multimap Reads'] = params.allow_multimap ? 'Allow' : 'Disallow'
if (params.allow_overlap) summary['Overlap Reads'] = params.allow_overlap ? 'Allow' : 'Disallow'
if (params.count_fractionally) summary['Fractional counting'] = params.count_fractionally ? 'Enabled' : 'Disabled'
if (params.group_features_type) summary['Biotype GTF field'] = params.group_features_type
summary['Min Mapped Reads'] = params.min_mapped_reads

summary['ERCC quantification mode']   = params.spike_in_ercc || params.spike_in_sirv ? 'On' : 'Off'
summary['SIRV quantification mode']   = params.spike_in_sirv ? 'On' : 'Off'

summary['Resource allocation for the entire workflow']  = "$params.entire_max_cpus cpus, $params.entire_max_memory memory"
summary['Max Resources']    = "$params.max_memory memory, $params.max_cpus cpus, $params.max_time time per job"
if (workflow.containerEngine) summary['Container'] = "$workflow.containerEngine - $workflow.container"
summary['Output dir']       = params.outdir
summary['Launch dir']       = workflow.launchDir
summary['Working dir']      = workflow.workDir
summary['Script dir']       = workflow.projectDir
summary['User']             = workflow.userName

summary['Config Profile'] = workflow.profile
if (params.config_profile_description) summary['Config Description'] = params.config_profile_description
if (params.config_profile_contact)     summary['Config Contact']     = params.config_profile_contact
if (params.config_profile_url)         summary['Config URL']         = params.config_profile_url
if (params.email || params.email_on_fail) {
    summary['E-mail Address']    = params.email
    summary['E-mail on failure'] = params.email_on_fail
    summary['MultiQC maxsize']   = params.max_multiqc_email_size
}
log.info summary.collect { k,v -> "${k.padRight(18)}: $v" }.join("\n")
log.info "-\033[2m--------------------------------------------------\033[0m-"

// Check the hostnames against configured profiles
checkHostname()

Channel.from(summary.collect{ [it.key, it.value] })
    .map { k,v -> "<dt>$k</dt><dd><samp>${v ?: '<span style=\"color:#999999;\">N/A</a>'}</samp></dd>" }
    .reduce { a, b -> return [a, b].join("\n            ") }
    .map { x -> """
    id: 'ramdaq-summary'
    description: " - this information is collected when the pipeline is started."
    section_name: 'ramdaq Workflow Summary'
    section_href: 'https://github.com/rikenbit/ramdaq'
    plot_type: 'html'
    data: |
        <dl class=\"dl-horizontal\">
            $x
        </dl>
    """.stripIndent() }
    .set { ch_workflow_summary }

///////////////////////////////////////////////////////////////////////////////
/*
* Parse software version numbers
*/
///////////////////////////////////////////////////////////////////////////////

process get_software_versions {
    label 'process_low'
    publishDir "${params.outdir}/pipeline_info", mode: 'copy',
        saveAs: { filename ->
                      if (filename.indexOf(".csv") > 0) filename
                      else null
                }

    output:
    file 'software_versions_mqc.yaml' into ch_software_versions_yaml
    file "software_versions.csv"

    script:
    """
    echo $workflow.manifest.version > v_pipeline.txt
    echo $workflow.nextflow.version > v_nextflow.txt
    fastqc --version > v_fastqc.txt
    multiqc --version > v_multiqc.txt
    fastq-mcf -V > v_fastqmcf.txt
    hisat2 --version > v_hisat2.txt
    samtools --version > v_samtools.txt
    bam2wig.py --version > v_bam2wig.txt
    bamtools --version > v_bamtools.txt
    read_distribution.py --version > v_read_distribution.txt
    infer_experiment.py --version > v_infer_experiment.txt
    inner_distance.py --version > v_inner_distance.txt
    junction_annotation.py --version > v_junction_annotation.txt
    featureCounts -v > v_featurecounts.txt
    Rscript -e "library(edgeR); write(x=as.character(packageVersion('edgeR')), file='v_edgeR.txt')"
    scrape_software_versions.py &> software_versions_mqc.yaml
    """
}


///////////////////////////////////////////////////////////////////////////////
/*
* STEP 1 - FastQC
*/
///////////////////////////////////////////////////////////////////////////////

process fastqc {
    label 'process_low'
    tag "$name"
    
    publishDir "${params.outdir}/fastqc", mode: 'copy',
        saveAs: { filename ->
                      filename.indexOf(".zip") > 0 ? "zips/$filename" : "$filename"
                }

    input:
    set val(name), file(reads) from ch_read_files_fastqc

    output:
    file "*_fastqc.{zip,html}" into ch_fastqc_results

    script:
    if (params.single_end) {
        newfastq = (reads.getName() =~ /\.gz$/) ? "${name}.raw.fastq.gz" : "${name}.raw.fastq"
        """
        ln -s $reads $newfastq
        fastqc --quiet --threads $task.cpus $newfastq
        """
    } else {
        newfastq1 = (reads[0].getName() =~ /\.gz$/) ? "${name}_1.raw.fastq.gz" : "${name}_1.raw.fastq"
        newfastq2 = (reads[1].getName() =~ /\.gz$/) ? "${name}_2.raw.fastq.gz" : "${name}_2.raw.fastq"
        """
        ln -s ${reads[0]} $newfastq1
        ln -s ${reads[1]} $newfastq2
        fastqc --quiet --threads $task.cpus $newfastq1
        fastqc --quiet --threads $task.cpus $newfastq2
        """
    }
}

///////////////////////////////////////////////////////////////////////////////
/*
* STEP 2 - Adapter Trimming
*/
///////////////////////////////////////////////////////////////////////////////

process fastqmcf  {
    tag "$name"

    publishDir "${params.outdir}/fastqmcf", mode: 'copy', overwrite: true
 
    input:
    set val(name), file(reads) from ch_read_files_fastqmcf
    file adapter from ch_adapter

    output:
    set val(name), file("*.trim.fastq.gz") into ch_trimmed_reads

    script:
    maxReadLength = params.maxReadLength > 0 ? "-L ${params.maxReadLength}" : ''
    minReadLength = params.minReadLength > 0 ? "-l ${params.minReadLength}" : ''
    skew = params.skew > 0 ? "-k ${params.skew}" : ''
    quality = params.quality > 0 ? "-q ${params.quality}" : ''

    if (params.single_end) {
        """
        fastq-mcf $adapter $reads -o ${name}.trim.fastq $maxReadLength $minReadLength $skew $quality ; gzip ${name}.trim.fastq
        """
    } else {
        """
        fastq-mcf $adapter ${reads[0]} ${reads[1]} -o ${name}_1.trim.fastq -o ${name}_2.trim.fastq $maxReadLength $minReadLength $skew $quality ; gzip ${name}_1.trim.fastq && gzip ${name}_2.trim.fastq
        """
    }
}

ch_trimmed_reads
    .into{
        ch_trimmed_reads_tofastqc;
        ch_trimmed_reads_tohisat2;
        ch_trimmed_reads_tosirv_hisat2;
        ch_trimmed_reads_tosirv_rsem
        ch_trimmed_reads_toallgene_rsem
    }

///////////////////////////////////////////////////////////////////////////////
/*
* STEP 3 - FastQC (trimmed reads)
*/
///////////////////////////////////////////////////////////////////////////////

process fastqc_trimmed {
    label 'process_low'
    tag "$name"
    
    publishDir "${params.outdir}/fastqc.trim", mode: 'copy',
        saveAs: { filename ->
                      filename.indexOf(".zip") > 0 ? "zips/$filename" : "$filename"
                }

    input:
    set val(name), file(reads) from ch_trimmed_reads_tofastqc

    output:
    file "*_fastqc.{zip,html}" into ch_trimmed_reads_fastqc_results

    script:
    if (params.single_end) {
        """
        fastqc --quiet --threads $task.cpus $reads
        """
    } else {
        """
        fastqc --quiet --threads $task.cpus ${reads[0]}
        fastqc --quiet --threads $task.cpus ${reads[1]}
        """
    }
}

///////////////////////////////////////////////////////////////////////////////
/*
* STEP 4-1 - Hisat2
*/
///////////////////////////////////////////////////////////////////////////////

process hisat2 {
    tag "$name"
    label 'process_high'
    
    publishDir "${params.outdir}/hisat2", mode: 'copy', overwrite: true,
        saveAs: { filename ->
                    filename.indexOf("_summary.txt") > 0 ? "logs/$filename" : "$filename"
                }

    input:
    set val(name), file(reads) from ch_trimmed_reads_tohisat2
    file hs2_indices from ch_hisat2_idx.collect()
    path tools_dir from ch_tools_dir

    output:
    set val(name), file("*.bam"), file("*.bai"), file("*.flagstat") into ch_hisat2_bam
    set val(name), file("${name}.bam"), file("${name}.bam.bai"), file("${name}.bam.flagstat") into ch_hisat2_bamsort
    set val(name), file("${name}.bam"), file("${name}.bam.flagstat") into ch_hisat2_bamcount
    file "*_summary.txt" into ch_alignment_logs, ch_totalseq

    script:
    def strandness = ''
    if (params.stranded == 'fr-firststrand') {
        strandness = params.single_end ? "--rna-strandness R" : "--rna-strandness RF"
    } else if (params.stranded == 'fr-secondstrand'){
        strandness = params.single_end ? "--rna-strandness F" : "--rna-strandness FR"
    }
    softclipping = params.softclipping ? '' : "--no-softclip"
    threads_num = params.hs_threads_num > 0 ? "-p ${params.hs_threads_num}" : ''
    index_base = hs2_indices[0].toString() - ~/.\d.ht2l?/

    if (params.single_end) {
        if (params.stranded && params.stranded != 'unstranded') {
            """
            hisat2 $softclipping $threads_num -x $index_base -U $reads $strandness --summary-file ${name}_summary.txt \\
            | samtools view -bS - | samtools sort - -o ${name}.bam
            samtools index ${name}.bam
            samtools flagstat ${name}.bam > ${name}.bam.flagstat

            bamtools filter -in ${name}.bam -out ${name}.forward.bam -script ${tools_dir}/bamtools_f_SE.json
            samtools index ${name}.forward.bam
            samtools flagstat ${name}.forward.bam > ${name}.forward.bam.flagstat

            bamtools filter -in ${name}.bam -out ${name}.reverse.bam -script ${tools_dir}/bamtools_r_SE.json
            samtools index ${name}.reverse.bam
            samtools flagstat ${name}.reverse.bam > ${name}.reverse.bam.flagstat
            """
        } else {
            """
            hisat2 $softclipping $threads_num -x $index_base -U $reads --summary-file ${name}_summary.txt \\
            | samtools view -bS - | samtools sort - -o ${name}.bam
            samtools index ${name}.bam
            samtools flagstat ${name}.bam > ${name}.bam.flagstat
            """
        }

    } else {
        if (params.stranded && params.stranded != 'unstranded') {
            """
            hisat2 $softclipping $threads_num -x $index_base -1 ${reads[0]} -2 ${reads[1]} $strandness --summary-file ${name}_summary.txt \\
            | samtools view -bS - | samtools sort - -o ${name}.bam
            samtools index ${name}.bam
            samtools flagstat ${name}.bam > ${name}.bam.flagstat

            bamtools filter -in ${name}.bam -out ${name}.forward.bam -script ${tools_dir}/bamtools_f_PE.json
            samtools index ${name}.forward.bam
            samtools flagstat ${name}.forward.bam > ${name}.forward.bam.flagstat

            bamtools filter -in ${name}.bam -out ${name}.reverse.bam -script ${tools_dir}/bamtools_r_PE.json
            samtools index ${name}.reverse.bam
            samtools flagstat ${name}.reverse.bam > ${name}.reverse.bam.flagstat

            samtools view -bS -f 0x40 ${name}.bam -o ${name}.R1.bam
            samtools index ${name}.R1.bam
            samtools flagstat ${name}.R1.bam > ${name}.R1.bam.flagstat

            samtools view -bS -f 0x80 ${name}.bam -o ${name}.R2.bam
            samtools index ${name}.R2.bam
            samtools flagstat ${name}.R2.bam > ${name}.R2.bam.flagstat
            """
        } else {
            """
            hisat2 $softclipping $threads_num -x $index_base -1 ${reads[0]} -2 ${reads[1]} --summary-file ${name}_summary.txt \\
            | samtools view -bS - | samtools sort - -o ${name}.bam
            samtools index ${name}.bam
            samtools flagstat ${name}.bam > ${name}.bam.flagstat

            samtools view -bS -f 0x40 ${name}.bam -o ${name}.R1.bam
            samtools index ${name}.R1.bam
            samtools flagstat ${name}.R1.bam > ${name}.R1.bam.flagstat

            samtools view -bS -f 0x80 ${name}.bam -o ${name}.R2.bam
            samtools index ${name}.R2.bam
            samtools flagstat ${name}.R2.bam > ${name}.R2.bam.flagstat
            """
        }
    }
}

process merge_hisat2_totalSeq {
    publishDir "${params.outdir}/merged_output_files", mode: 'copy'

    input:
    file input_files from ch_totalseq.collect()

    output:
    file 'merged_hisat2_totalseq.txt' into ch_totalseq_merged

    script:
    command = input_files.collect{filename ->
        "awk '{if (FNR==1){print FILENAME, FNR, NR, \$0}}' ${filename} | sed 's:_summary.txt::' | cut -f1,4 --delim=\" \" >> merged_hisat2_totalseq.txt"}.join(" && ")
    """
    $command
    """
}

ch_totalseq_merged
    .into{
        ch_totalseq_assignedgenome
        ch_totalseq_fcount_allgene
    }

// Get total number of mapped reads from flagstat file
def get_mapped_from_flagstat(flagstat_file) {
    def mapped = 0
    flagstat_file.eachLine { line ->
        if (line.contains(' mapped (')) {
            mapped = line.tokenize().first().toInteger()
        }
    }
    return mapped
}

// Function that checks the number of mapped reads from flagstat output
// and returns true if > params.min_mapped_reads and otherwise false
def check_mapped(name,flagstat_path,min_mapped_reads=10) {
    def flagstat_file = new File(flagstat_path.toString())
    //mapped = get_mapped_from_flagstat(flagstat_file)
    def mapped = 0
    flagstat_file.eachLine { line ->
        if (line.contains(' mapped (')) {
            mapped = line.tokenize().first().toInteger()
        }
    }
    if (mapped < min_mapped_reads.toInteger()) {
        log.info ">>>> $name FAILED MAPPED READ THRESHOLD: ${mapped} < ${params.min_mapped_reads}. IGNORING FOR FURTHER DOWNSTREAM ANALYSIS! <<<<"
        return false
    } else {
        return true
    }
}

// Remove samples that failed mapped read threshold
ch_hisat2_bam
    .transpose()
    .into{ 
        ch_hisat2_bam_filter
        ch_debug }

//ch_debug.println()

ch_hisat2_bam_filter
    .filter { name, bam, bai, flagstat -> check_mapped(name,flagstat,params.min_mapped_reads) }
    .map { it[0..2] }
    .into{
        hisat2_output_toreadcoverage
        hisat2_output_torseqc
        hisat2_output_tobam2wig
    }

ch_hisat2_bamsort
    .filter { name, bam, bai, flagstat -> check_mapped(name,flagstat,params.min_mapped_reads) }
    .map { it[0..2] }
    .into { 
        hisat2_output_tofcount
        hisat2_output_tofcount_mt
        hisat2_output_tofcount_rrna
        hisat2_output_tofcount_histone
    }

ch_hisat2_bamcount
    .filter { name, bam, flagstat -> check_mapped(bam.baseName,flagstat,params.min_mapped_reads) }
    .map { it[1] }
    .set { ch_hisat2_bamcount }

///////////////////////////////////////////////////////////////////////////////
/*
* STEP 4-2 - Hisat2 (SIRVome)
*/
///////////////////////////////////////////////////////////////////////////////

process hisat2_sirv {
    tag "$name"
    label 'process_high'
    
    publishDir "${params.outdir}/hisat2_sirv", mode: 'copy', overwrite: true,
        saveAs: { filename ->
                    filename.indexOf("_summary_sirv.txt") > 0 ? "logs/$filename" : "$filename"
                }
    when:
    params.spike_in_sirv && ch_hisat2_sirv_idx

    input:
    set val(name), file(reads) from ch_trimmed_reads_tosirv_hisat2
    file sirv_indices from ch_hisat2_sirv_idx.collect()
    path tools_dir from ch_tools_dir_sirv

    output:
    set val(name), file("*.bam"), file("*.bai"), file("*.flagstat") into ch_sirv_bamsort

    script:
    def strandness = ''
    if (params.stranded == 'fr-firststrand') {
        strandness = params.single_end ? "--rna-strandness R" : "--rna-strandness RF"
    } else if (params.stranded == 'fr-secondstrand'){
        strandness = params.single_end ? "--rna-strandness F" : "--rna-strandness FR"
    }
    softclipping = params.softclipping ? '' : "--no-softclip"
    threads_num = params.hs_threads_num > 0 ? "-p ${params.hs_threads_num}" : ''
    index_base = sirv_indices[0].toString() - ~/.\d.ht2l?/

    if (params.single_end) {
        if (params.stranded && params.stranded != 'unstranded') {
            """
            hisat2 $softclipping $threads_num -x $index_base -U $reads $strandness --summary-file ${name}_summary_sirv.txt \\
            | samtools view -bS - | samtools sort - -o ${name}.sirv.bam
            samtools index ${name}.sirv.bam
            samtools flagstat ${name}.sirv.bam > ${name}.sirv.bam.flagstat

            bamtools filter -in ${name}.sirv.bam -out ${name}_forward.sirv.bam -script ${tools_dir}/bamtools_f_SE.json
            samtools index ${name}_forward.sirv.bam
            samtools flagstat ${name}_forward.sirv.bam > ${name}_forward.sirv.bam.flagstat
            
            bamtools filter -in ${name}.sirv.bam -out ${name}_reverse.sirv.bam -script ${tools_dir}/bamtools_r_SE.json
            samtools index ${name}_reverse.sirv.bam
            samtools flagstat ${name}_reverse.sirv.bam > ${name}_reverse.sirv.bam.flagstat
            """
        } else {
            """
            hisat2 $softclipping $threads_num -x $index_base -U $reads --summary-file ${name}_summary_sirv.txt \\
            | samtools view -bS - | samtools sort - -o ${name}.sirv.bam
            samtools index ${name}.sirv.bam
            samtools flagstat ${name}.sirv.bam > ${name}.sirv.bam.flagstat
            """
        }

    } else {
        if (params.stranded && params.stranded != 'unstranded') {
            """
            hisat2 $softclipping $threads_num -x $index_base -1 ${reads[0]} -2 ${reads[1]} $strandness --summary-file ${name}_summary_sirv.txt \\
            | samtools view -bS - | samtools sort - -o ${name}.sirv.bam
            samtools index ${name}.sirv.bam
            samtools flagstat ${name}.sirv.bam > ${name}.sirv.bam.flagstat

            bamtools filter -in ${name}.sirv.bam -out ${name}_forward.sirv.bam -script ${tools_dir}/bamtools_f_PE.json
            samtools index ${name}_forward.sirv.bam
            samtools flagstat ${name}_forward.sirv.bam > ${name}_forward.sirv.bam.flagstat
            
            bamtools filter -in ${name}.sirv.bam -out ${name}_reverse.sirv.bam -script ${tools_dir}/bamtools_r_PE.json
            samtools index ${name}_reverse.sirv.bam
            samtools flagstat ${name}_reverse.sirv.bam > ${name}_reverse.sirv.bam.flagstat

            samtools view -bS -f 0x40 ${name}.sirv.bam -o ${name}_R1.sirv.bam
            samtools index ${name}_R1.sirv.bam
            samtools flagstat ${name}_R1.sirv.bam > ${name}_R1.sirv.bam.flagstat

            samtools view -bS -f 0x80 ${name}.sirv.bam -o ${name}_R2.sirv.bam
            samtools index ${name}_R2.sirv.bam
            samtools flagstat ${name}_R2.sirv.bam > ${name}_R2.sirv.bam.flagstat
            """
        } else {
            """
            hisat2 $softclipping $threads_num -x $index_base -1 ${reads[0]} -2 ${reads[1]} --summary-file ${name}_summary_sirv.txt \\
            | samtools view -bS - | samtools sort - -o ${name}.sirv.bam
            samtools index ${name}.sirv.bam
            samtools flagstat ${name}.sirv.bam > ${name}.sirv.bam.flagstat
            """
        }
    }
}

def check_bam_forsirv(name,flagstat_path,min_mapped_reads=10) {
    
    //trim R1 or R2 bams
    if (name.indexOf("_R1") > 0 || name.indexOf("_R2") > 0){
        return false
    }
    
    def flagstat_file = new File(flagstat_path.toString())
    //mapped = get_mapped_from_flagstat(flagstat_file)
    def mapped = 0
    flagstat_file.eachLine { line ->
        if (line.contains(' mapped (')) {
            mapped = line.tokenize().first().toInteger()
        }
    }
    if (mapped < min_mapped_reads.toInteger()) {
        log.info ">>>> $name FAILED MAPPED READ THRESHOLD: ${mapped} < ${params.min_mapped_reads}. IGNORING FOR FURTHER DOWNSTREAM ANALYSIS! <<<<"
        return false
    } else {
        return true
    }
}

ch_sirv_bamsort
    .transpose()
    .filter { name, bam, bai, flagstat -> check_bam_forsirv(bam.baseName,flagstat,params.min_mapped_reads) }
    .map { it[0..2] }
    .set { 
        output_toreadcoverage_sirv
        //hisat2_output_tofcount_sirv
    }

///////////////////////////////////////////////////////////////////////////////
/*
* STEP 5-1 - RSEM (SIRVome)
*/
///////////////////////////////////////////////////////////////////////////////

process rsem_bowtie2_sirv {
    tag "$name"
    label 'process_high'
    
    publishDir "${params.outdir}/rsem_bowtie2_sirv", mode: 'copy', overwrite: true,
        saveAs: { filename ->
                    filename.indexOf(".log") > 0 ? "logs/$filename" : "$filename"
                }
    when:
    params.spike_in_sirv && ch_rsem_sirv_idx

    input:
    set val(name), file(reads) from ch_trimmed_reads_tosirv_rsem
    file sirv_indices from ch_rsem_sirv_idx.collect()

    output:
    file "*.isoforms.results" into rsem_results_sirv_to_merge
    file "*.results"
    file "*.log"

    script:
    def strandness = ''
    if (params.stranded == 'fr-firststrand') {
        strandness = "--strandedness reverse"
    } else if (params.stranded == 'fr-secondstrand'){
        strandness = "--strandedness forward"
    }
    index_base = sirv_indices[0].toString().split('\\.')[0]
    threads_num = params.rsem_threads_num > 0 ? "-p ${params.rsem_threads_num}" : ''

    if (params.single_end) {
        if (params.stranded && params.stranded != 'unstranded') {
            """
            rsem-calculate-expression $threads_num $strandness $reads --bowtie2 --bowtie2-path /opt/conda/envs/ramdaq-1.0dev/bin/ $index_base ${name}.sirv
            samtools sort ${name}.sirv.transcript.bam -o ${name}.sirv.rsem.bam
            samtools index ${name}.sirv.rsem.bam
            samtools flagstat ${name}.sirv.rsem.bam > ${name}.sirv.rsem.bam.flagstat
            rm ${name}.sirv.transcript.bam
            """
        } else {
            """
            rsem-calculate-expression $threads_num $reads --bowtie2 --bowtie2-path /opt/conda/envs/ramdaq-1.0dev/bin/ $index_base ${name}.sirv
            samtools sort ${name}.sirv.transcript.bam -o ${name}.sirv.rsem.bam
            samtools index ${name}.sirv.rsem.bam
            samtools flagstat ${name}.sirv.rsem.bam > ${name}.sirv.rsem.bam.flagstat
            rm ${name}.sirv.transcript.bam
            """
        }

    } else {
        if (params.stranded && params.stranded != 'unstranded') {
            """
            rsem-calculate-expression $threads_num $strandness --paired-end ${reads[0]} ${reads[1]} --bowtie2 --bowtie2-path /opt/conda/envs/ramdaq-1.0dev/bin/ \\
            $index_base ${name}.sirv
            samtools sort ${name}.sirv.transcript.bam -o ${name}.sirv.rsem.bam
            samtools index ${name}.sirv.rsem.bam
            samtools flagstat ${name}.sirv.rsem.bam > ${name}.sirv.rsem.bam.flagstat
            rm ${name}.sirv.transcript.bam
            """
        } else {
            """
            rsem-calculate-expression $threads_num --paired-end ${reads[0]} ${reads[1]} --bowtie2 --bowtie2-path /opt/conda/envs/ramdaq-1.0dev/bin/ \\
            $index_base ${name}.sirv
            samtools sort ${name}.sirv.transcript.bam -o ${name}.sirv.rsem.bam
            samtools index ${name}.sirv.rsem.bam
            samtools flagstat ${name}.sirv.rsem.bam > ${name}.sirv.rsem.bam.flagstat
            rm ${name}.sirv.transcript.bam
            """
        }
    }
}

process merge_sirv_isoforms {
    publishDir "${params.outdir}/merged_output_files", mode: 'copy'

    input:
    file input_files from rsem_results_sirv_to_merge.collect()

    output:
    file 'merged_rsemResults_SIRVome_isoforms.txt'

    script:
    // Redirection (the `<()`) for the win!
    // Geneid in 1st column and gene_name in 7th
    gene_ids = "<(tail -n +1 ${input_files[0]} | cut -f1,2 )"
    counts = input_files.collect{filename ->
      // Remove first line and take third column
      "<(tail -n +1 ${filename} | sed 's:TPM:${filename}:' | sed 's:.sirv.rsem.isoforms.results::' | cut -f6)"}.join(" ")
    """
    paste $gene_ids $counts > merged_rsemResults_SIRVome_isoforms.txt
    """
  }

///////////////////////////////////////////////////////////////////////////////
/*
* STEP 5-2 - RSEM (All genes)
*/
///////////////////////////////////////////////////////////////////////////////

process rsem_bowtie2_allgenes {
    tag "$name"
    label 'process_high'
    
    publishDir "${params.outdir}/rsem_bowtie2_allgenes", mode: 'copy', overwrite: true,
        saveAs: { filename ->
                    filename.indexOf(".log") > 0 ? "logs/$filename" : "$filename"
                }
    when:
    ch_rsem_allgene_idx

    input:
    set val(name), file(reads) from ch_trimmed_reads_toallgene_rsem
    file sirv_indices from ch_rsem_allgene_idx.collect()

    output:
    file "*.isoforms.results" into rsem_results_isoforms_to_merge
    file "*.genes.results" into rsem_results_genes_to_merge
    file "*.results"
    file "*.log"
    file "*.stat/*.cnt" into rsem_results_genes_stat

    script:
    def strandness = ''
    if (params.stranded == 'fr-firststrand') {
        strandness = "--strandedness reverse"
    } else if (params.stranded == 'fr-secondstrand'){
        strandness = "--strandedness forward"
    }
    index_base = sirv_indices[0].toString().split('\\.')[0]
    threads_num = params.rsem_threads_num > 0 ? "-p ${params.rsem_threads_num}" : ''

    if (params.single_end) {
        if (params.stranded && params.stranded != 'unstranded') {
            """
            rsem-calculate-expression $threads_num $strandness $reads --bowtie2 --bowtie2-path /opt/conda/envs/ramdaq-1.0dev/bin/ $index_base ${name}
            samtools sort ${name}.transcript.bam -o ${name}.rsem.bam
            samtools index ${name}.rsem.bam
            samtools flagstat ${name}.rsem.bam > ${name}.rsem.bam.flagstat
            rm ${name}.transcript.bam
            """
        } else {
            """
            rsem-calculate-expression $threads_num $reads --bowtie2 --bowtie2-path /opt/conda/envs/ramdaq-1.0dev/bin/ $index_base ${name}
            samtools sort ${name}.transcript.bam -o ${name}.rsem.bam
            samtools index ${name}.rsem.bam
            samtools flagstat ${name}.rsem.bam > ${name}.rsem.bam.flagstat
            rm ${name}.transcript.bam
            """
        }

    } else {
        if (params.stranded && params.stranded != 'unstranded') {
            """
            rsem-calculate-expression $threads_num $strandness --paired-end ${reads[0]} ${reads[1]} --bowtie2 --bowtie2-path /opt/conda/envs/ramdaq-1.0dev/bin/ \\
            $index_base ${name}
            samtools sort ${name}.transcript.bam -o ${name}.rsem.bam
            samtools index ${name}.rsem.bam
            samtools flagstat ${name}.rsem.bam > ${name}.rsem.bam.flagstat
            rm ${name}.transcript.bam
            """
        } else {
            """
            rsem-calculate-expression $threads_num --paired-end ${reads[0]} ${reads[1]} --bowtie2 --bowtie2-path /opt/conda/envs/ramdaq-1.0dev/bin/ \\
            $index_base ${name}
            samtools sort ${name}.transcript.bam -o ${name}.rsem.bam
            samtools index ${name}.rsem.bam
            samtools flagstat ${name}.rsem.bam > ${name}.rsem.bam.flagstat
            rm ${name}.transcript.bam
            """
        }
    }
}

process merge_rsemresults_genes {
    publishDir "${params.outdir}/merged_output_files", mode: 'copy'

    input:
    file input_files from rsem_results_genes_to_merge.collect()

    output:
    file 'merged_rsemResults_genes_TPM.txt' into rsem_tpm_gene

    script:
    // Redirection (the `<()`) for the win!
    // Geneid in 1st column and gene_name in 7th
    gene_ids = "<(tail -n +1 ${input_files[0]} | cut -f1,2 )"
    counts = input_files.collect{filename ->
      // Remove first line and take third column
      "<(tail -n +1 ${filename} | sed 's:TPM:${filename}:' | sed 's:.sirv.rsem.genes.results::' | cut -f6)"}.join(" ")
    """
    paste $gene_ids $counts > merged_rsemResults_genes_TPM.txt
    """
  }

process merge_rsemresults_isoforms {
    publishDir "${params.outdir}/merged_output_files", mode: 'copy'

    input:
    file input_files from rsem_results_isoforms_to_merge.collect()

    output:
    file 'merged_rsemResults_isoforms_TPM.txt' into rsem_tpm_ts

    script:
    // Redirection (the `<()`) for the win!
    // Geneid in 1st column and gene_name in 7th
    gene_ids = "<(tail -n +1 ${input_files[0]} | cut -f1,2 )"
    counts = input_files.collect{filename ->
      // Remove first line and take third column
      "<(tail -n +1 ${filename} | sed 's:TPM:${filename}:' | sed 's:.sirv.rsem.isoforms.results::' | cut -f6)"}.join(" ")
    """
    paste $gene_ids $counts > merged_rsemResults_isoforms_TPM.txt
    """
  }

///////////////////////////////////////////////////////////////////////////////
/*
* STEP 5-3 - create plot from RSEM TPM counts (genes)
*/
///////////////////////////////////////////////////////////////////////////////

process create_plots_rsem_gene {
    label 'process_medium'
    publishDir "${params.outdir}/plots_from_tpmcounts_rsem", mode: 'copy'

    input:
    file tpm_count from rsem_tpm_gene
    file detgene_header from ch_num_of_gene_rsem_header

    output:
    file "*.{txt,pdf,csv}" into plots_from_rsem_gene_results

    script:
    """
    drawplot_tpm_counts.r $tpm_count rsem
    cat $detgene_header barplot_num_of_gene_rsem.csv >> tmp_file
    mv tmp_file barplot_num_of_gene_rsem_mqc.csv
    
    """

}

///////////////////////////////////////////////////////////////////////////////
/*
* STEP 5-4 - create plot from RSEM TPM counts (transcripts)
*/
///////////////////////////////////////////////////////////////////////////////

process create_plots_rsem_ts {
    label 'process_medium'
    publishDir "${params.outdir}/plots_from_tpmcounts_rsem", mode: 'copy'

    input:
    file tpm_count from rsem_tpm_ts
    file detts_header from ch_num_of_ts_rsem_header

    output:
    file "*.{txt,pdf,csv}" into plots_from_rsem_ts_results

    script:
    """
    drawplot_tpm_counts_ts.r $tpm_count
    cat $detts_header barplot_num_of_ts_rsem.csv >> tmp_file
    mv tmp_file barplot_num_of_ts_rsem_mqc.csv
    
    """

}


///////////////////////////////////////////////////////////////////////////////
/*
* STEP 6 - Bam to BigWig
*/
///////////////////////////////////////////////////////////////////////////////

process bam2wig {
    tag "$name"
    label 'process_medium'
    
    publishDir "${params.outdir}/bam_bigwig", mode: 'copy', overwrite: true

    input:
    set val(name), file(bam), file(bai) from hisat2_output_tobam2wig
    file chrsize from ch_chrsize

    output:
    file "*.bw"
    file "*.wig"

    script:
    """
    bam2wig.py -i ${bam} -s $chrsize -u -o ${bam.baseName}
    """

}

///////////////////////////////////////////////////////////////////////////////
/*
* STEP 7 - RSeQC
*/
///////////////////////////////////////////////////////////////////////////////

process adjust_bed_noncoding {
    label 'process_low'
    publishDir "${params.outdir}/rseqc/", mode: 'copy'

    input:
    file bed from ch_bed

    output:
    file 'adjusted.bed' into ch_bed_adjusted

    script:
    """
    adjust_bed_noncoding.r $bed
    """
}

process rseqc  {
    tag "$name"
    label 'process_high'

    publishDir "${params.outdir}/rseqc", mode: 'copy',
        saveAs: {filename ->
            if (filename.indexOf("readdist.txt") > 0)         "read_distribution/$filename"
            else if (filename.indexOf("inferexp.txt") > 0)    "infer_experiment/$filename"
            else if (filename.indexOf("inner_distance") > 0)  "inner_distance/$filename"
            else if (filename.indexOf("junction") > 0)        "junction_annotation/$filename"
            else if (filename.indexOf("splice_events") > 0)   "junction_annotation/$filename"
            else "$filename"
    }

    input:
    set val(name), file(bam), file(bai) from hisat2_output_torseqc
    file bed from ch_bed_adjusted

    output:
    file "*.{txt,pdf,r,xls,log}" into rseqc_results
    file "${name}.readdist.txt" optional true into ch_totalread
    
    script:
    if (params.single_end) {
        """
        read_distribution.py -i $bam -r $bed > ${bam.baseName}.readdist.txt
        infer_experiment.py -i $bam -r $bed > ${bam.baseName}.inferexp.txt
        junction_annotation.py -i $bam -o ${bam.baseName} -r $bed 2> ${bam.baseName}.junction_annotation.log
        """
    } else {
        """
        read_distribution.py -i $bam -r $bed > ${bam.baseName}.readdist.txt
        infer_experiment.py -i $bam -r $bed > ${bam.baseName}.inferexp.txt
        inner_distance.py -i $bam -o ${bam.baseName} -r $bed
        junction_annotation.py -i $bam -o ${bam.baseName} -r $bed 2> ${bam.baseName}.junction_annotation.log
        """
    }

}

process merge_readDist_totalRead {
    publishDir "${params.outdir}/merged_output_files", mode: 'copy'

    input:
    file input_files from ch_totalread.collect()

    output:
    file 'merged_readdist_totalread.txt' into ch_totalread_merged

    script:
    command = input_files.collect{filename ->
        "awk '{if (FNR==1){print FILENAME, FNR, NR, \$0}}' ${filename} | sed 's:.readdist.txt::' | cut -f1,24 --delim=\" \" >> merged_readdist_totalread.txt"}.join(" && ")
    """
    $command
    """
}

///////////////////////////////////////////////////////////////////////////////
/*
* STEP 8-1 - readcoverage.jl
*/
///////////////////////////////////////////////////////////////////////////////

process readcoverage  {
    tag "$name"
    label 'process_high'
    container "yuifu/readcoverage.jl:0.1.2-workaround"

    publishDir "${params.outdir}/rseqc", mode: 'copy',
        saveAs: {filename ->
            if (filename.indexOf("geneBodyCoverage.txt") > 0) "genebody_coverage/$filename"
            else "$filename"
    }

    input:
    set val(name), file(bam), file(bai) from hisat2_output_toreadcoverage
    file bed from ch_bed

    output:
    file "*.txt" into readcov_results
    
    script:
    """
    julia /opt/run.jl relcov $bam $bed ${bam.baseName}
    """
}

rseqc_results_merge = rseqc_results
    .concat(readcov_results)

///////////////////////////////////////////////////////////////////////////////
/*
* STEP 8-2 - readcoverage.jl (SIRV genes)
*/
///////////////////////////////////////////////////////////////////////////////


process readcoverage_sirv  {
    tag "$name"
    container "yuifu/readcoverage.jl:0.1.2-workaround"

    publishDir "${params.outdir}/readcoverage_SIRVome", mode: 'copy'

    when:
    !params.suppress_sirv_coverage

    input:
    set val(name), file(bam), file(bai) from output_toreadcoverage_sirv

    output:
    file "*.txt" into readcov_sirv_results
    
    script:
    leftpos = [1001, 14644, 22555, 34498, 51620, 67226, 81063, 230020, 235017, 240016, 245017, 252017, 259017, 266017, 275018, 284018, 293018, 303959, 314960, 325930, 338959, 351958]
    rightpos = [11643, 19554, 31497, 48619, 64225, 78062, 228019, 234016, 239015, 244016, 251016, 258016, 265016, 274017, 283017, 292017, 302958, 313959, 324929, 337958, 350957, 363957]
    sirvname = ["SIRV1", "SIRV2", "SIRV3", "SIRV4", "SIRV5", "SIRV6", "SIRV7", "SIRV4001", "SIRV4002", "SIRV4003", "SIRV6001", "SIRV6002", "SIRV6003", "SIRV8001", "SIRV8002", "SIRV8003", "SIRV10001", "SIRV10002", "SIRV10003", "SIRV12001", "SIRV12002", "SIRV12003"]
    filename = bam.name.replaceAll('.sirv.bam', '')

    def command = ''
    for( int i=0; i<sirvname.size(); i++ ) {
        command += "julia /opt/run.jl coverage $bam SIRVomeERCCome ${leftpos[i]} ${rightpos[i]} ${filename}.${sirvname[i]}; " 
    } 
    command
}

process merge_readcoverage_sirv {
    publishDir "${params.outdir}/merged_output_files", mode: 'copy'

    input:
    file input_files from readcov_sirv_results.collect()

    output:
    file '*.tsv' into ch_readcoverage_sirv_merged

    script:
    command = input_files.collect{filename ->
        "awk -v filebasename=${filename.name} 'BEGIN{OFS=\"\t\"; bam=filebasename; sirv=filebasename; sub(\"\\..+?.readCoverage.txt\", \"\", bam); sub(\".readCoverage.txt\", \"\", sirv); sub(\".+\\.\", \"\", sirv);}{print sirv, \$1, \$2, bam}' ${filename} >> merged_readcoverage_SIRVome.tsv"}.join(" && ")

    """
    echo -e "SIRV\tposition\tcoverage\tbam" > merged_readcoverage_SIRVome.tsv
    
    $command
    """
}


///////////////////////////////////////////////////////////////////////////////
/*
* STEP 9-1 - FeatureCounts (All-genes GTF) 
*/
///////////////////////////////////////////////////////////////////////////////

process featureCounts  {
    tag "$name"

    publishDir "${params.outdir}/featureCounts", mode: 'copy',
        saveAs: {filename ->
            if (filename.indexOf("biotype_counts") > 0) "biotype_counts/$filename"
            else if (filename.indexOf("_gene.featureCounts.txt.summary") > 0) "gene_count_summaries/$filename"
            else if (filename.indexOf("_gene.featureCounts.txt") > 0) "gene_counts/$filename"
            else "$filename"
    }

    input:
    set val(name), file(bam), file(bai) from hisat2_output_tofcount
    file gtf from ch_gtf
    file biotypes_header from ch_biotypes_header.collect()

    output:
    file "${name}_gene.featureCounts.txt" into geneCounts, featureCounts_to_merge
    file "${name}_gene.featureCounts.txt.summary" into featureCounts_logs
    file "${name}_biotype_counts*mqc.{txt,tsv}" optional true into featureCounts_biotype
    
    script:

    isPairedEnd = params.single_end ? '' : "-p"
    if (params.stranded && params.stranded == 'fr-firststrand') {
        isStrandSpecific = "-s 2"
    } else if (params.stranded && params.stranded == 'fr-secondstrand'){
        isStrandSpecific = "-s 1"
    } else {
        isStrandSpecific = ''
    }
    extraAttributes = params.extra_attributes ? "--extraAttributes ${params.extra_attributes}" : ''
    allow_multimap = params.allow_multimap ? "-M" : ''
    allow_overlap = params.allow_overlap ? "-O" : ''
    count_fractionally = params.count_fractionally ? "--fraction" : ''
    threads_num = params.fc_threads_num > 0 ? "-T ${params.fc_threads_num}" : ''
    biotype = params.group_features_type

    biotype_qc = "featureCounts -a $gtf -g $biotype -o ${name}_biotype.featureCounts.txt $isPairedEnd $isStrandSpecific ${bam}"
    mod_biotype = "cut -f 1,7 ${name}_biotype.featureCounts.txt | tail -n +3 | cat $biotypes_header - >> ${name}_biotype_counts_mqc.txt"

    """
    featureCounts -a $gtf -g ${params.group_features} -t ${params.count_type} -o ${name}_gene.featureCounts.txt  \\
    $isPairedEnd $isStrandSpecific $extraAttributes $count_fractionally $allow_multimap $allow_overlap $threads_num ${bam}
    
    $biotype_qc
    $mod_biotype
    """
}

process merge_featureCounts {
    publishDir "${params.outdir}/merged_output_files", mode: 'copy'

    input:
    file input_files from featureCounts_to_merge.collect()

    output:
    file 'merged_featureCounts_gene.txt' into ch_tpm_count, ch_fcounts_allgene_merged

    script:
    // Redirection (the `<()`) for the win!
    // Geneid in 1st column and gene_name in 7th
    gene_ids = "<(tail -n +2 ${input_files[0]} | cut -f1,6,7 )"
    counts = input_files.collect{filename ->
      // Remove first line and take third column
      "<(tail -n +2 ${filename} | sed 's:.bam::' | cut -f8)"}.join(" ")
    """
    paste $gene_ids $counts > merged_featureCounts_gene.txt
    """
  }

process calc_TPMCounts {
    label 'process_low'
    publishDir "${params.outdir}/merged_output_files", mode: 'copy'

    input:
    file input_file from ch_tpm_count

    output:
    file '*_TPM.txt' into tpmcount_plot, tpmcount_merged
    file '*_ERCC.txt' optional true into ercccount_chk
    file '*_ERCC_log.txt' optional true into ercccount_merged

    script:
    """
    calc_TPMCounts.r $input_file
    """
}

ercc_list = ercccount_chk.toList() 

///////////////////////////////////////////////////////////////////////////////
/*
* STEP 9-2 - FeatureCounts (Mitochondrial GTF) 
*/
///////////////////////////////////////////////////////////////////////////////

process featureCounts_mt  {
    tag "$name"

    publishDir "${params.outdir}/featureCounts_Mitocondria", mode: 'copy',
        saveAs: {filename ->
            if (filename.indexOf("_mt.featureCounts.txt.summary") > 0) "mt_count_summaries/$filename"
            else if (filename.indexOf("_mt.featureCounts.txt") > 0) "mt_counts/$filename"
            else "$filename"
    }

    input:
    set val(name), file(bam), file(bai) from hisat2_output_tofcount_mt
    file gtf from ch_mt_gtf

    output:
    file "${name}_mt.featureCounts.txt" into featureCounts_to_merge_mt
    file "${name}_mt.featureCounts.txt.summary" into featureCounts_logs_mt

    script:

    isPairedEnd = params.single_end ? '' : "-p"
    if (params.stranded && params.stranded == 'fr-firststrand') {
        isStrandSpecific = "-s 2"
    } else if (params.stranded && params.stranded == 'fr-secondstrand'){
        isStrandSpecific = "-s 1"
    } else {
        isStrandSpecific = ''
    }
    extraAttributes = params.extra_attributes ? "--extraAttributes ${params.extra_attributes}" : ''
    allow_multimap = params.allow_multimap ? "-M" : ''
    allow_overlap = params.allow_overlap ? "-O" : ''
    count_fractionally = params.count_fractionally ? "--fraction" : ''
    threads_num = params.fc_threads_num > 0 ? "-T ${params.fc_threads_num}" : ''

    """
    featureCounts -a $gtf -g ${params.group_features} -t ${params.count_type} -o ${name}_mt.featureCounts.txt  \\
    $isPairedEnd $isStrandSpecific $extraAttributes $count_fractionally $allow_multimap $allow_overlap $threads_num ${bam}
    
    """
}

process merge_featureCounts_mt {
    publishDir "${params.outdir}/merged_output_files", mode: 'copy'

    input:
    file input_files from featureCounts_to_merge_mt.collect()

    output:
    file 'merged_featureCounts_gene_mt.txt' into ch_fcounts_mt_merged

    script:
    // Redirection (the `<()`) for the win!
    // Geneid in 1st column and gene_name in 7th
    gene_ids = "<(tail -n +2 ${input_files[0]} | cut -f1,6,7 )"
    counts = input_files.collect{filename ->
      // Remove first line and take third column
      "<(tail -n +2 ${filename} | sed 's:.bam::' | cut -f8)"}.join(" ")
    """
    paste $gene_ids $counts > merged_featureCounts_gene_mt.txt
    """
  }

///////////////////////////////////////////////////////////////////////////////
/*
* STEP 9-3 - FeatureCounts (rRNA GTF) 
*/
///////////////////////////////////////////////////////////////////////////////

process featureCounts_rrna  {
    tag "$name"

    publishDir "${params.outdir}/featureCounts_rRNA", mode: 'copy',
        saveAs: {filename ->
            if (filename.indexOf("_rrna.featureCounts.txt.summary") > 0) "rrna_count_summaries/$filename"
            else if (filename.indexOf("_rrna.featureCounts.txt") > 0) "rrna_counts/$filename"
            else "$filename"
    }

    input:
    set val(name), file(bam), file(bai) from hisat2_output_tofcount_rrna
    file gtf from ch_rrna_gtf

    output:
    file "${name}_rrna.featureCounts.txt" into featureCounts_to_merge_rrna
    file "${name}_rrna.featureCounts.txt.summary" into featureCounts_logs_rrna

    script:

    isPairedEnd = params.single_end ? '' : "-p"
    if (params.stranded && params.stranded == 'fr-firststrand') {
        isStrandSpecific = "-s 2"
    } else if (params.stranded && params.stranded == 'fr-secondstrand'){
        isStrandSpecific = "-s 1"
    } else {
        isStrandSpecific = ''
    }
    extraAttributes = params.extra_attributes ? "--extraAttributes ${params.extra_attributes}" : ''
    allow_multimap = params.allow_multimap ? "-M" : ''
    allow_overlap = params.allow_overlap ? "-O" : ''
    count_fractionally = params.count_fractionally ? "--fraction" : ''
    threads_num = params.fc_threads_num > 0 ? "-T ${params.fc_threads_num}" : ''

    """
    featureCounts -a $gtf -g ${params.group_features} -t ${params.count_type} -o ${name}_rrna.featureCounts.txt  \\
    $isPairedEnd $isStrandSpecific $extraAttributes $count_fractionally $allow_multimap $allow_overlap $threads_num ${bam}
    
    """
}

process merge_featureCounts_rrna {
    publishDir "${params.outdir}/merged_output_files", mode: 'copy'

    input:
    file input_files from featureCounts_to_merge_rrna.collect()

    output:
    file 'merged_featureCounts_gene_rrna.txt' into ch_fcounts_rrna_merged

    script:
    // Redirection (the `<()`) for the win!
    // Geneid in 1st column and gene_name in 7th
    gene_ids = "<(tail -n +2 ${input_files[0]} | cut -f1,6,7 )"
    counts = input_files.collect{filename ->
      // Remove first line and take third column
      "<(tail -n +2 ${filename} | sed 's:.bam::' | cut -f8)"}.join(" ")
    """
    paste $gene_ids $counts > merged_featureCounts_gene_rrna.txt
    """
  }

///////////////////////////////////////////////////////////////////////////////
/*
* STEP 9-4 - FeatureCounts (Histone GTF) 
*/
///////////////////////////////////////////////////////////////////////////////

process featureCounts_histone  {
    tag "$name"

    publishDir "${params.outdir}/featureCounts_Histone", mode: 'copy',
        saveAs: {filename ->
            if (filename.indexOf("_histone.featureCounts.txt.summary") > 0) "histone_count_summaries/$filename"
            else if (filename.indexOf("_histone.featureCounts.txt") > 0) "histone_counts/$filename"
            else "$filename"
    }

    input:
    set val(name), file(bam), file(bai) from hisat2_output_tofcount_histone
    file gtf from ch_histone_gtf

    output:
    file "${name}_histone.featureCounts.txt" into featureCounts_to_merge_histone
    file "${name}_histone.featureCounts.txt.summary" into featureCounts_logs_histone

    script:

    isPairedEnd = params.single_end ? '' : "-p"
    if (params.stranded && params.stranded == 'fr-firststrand') {
        isStrandSpecific = "-s 2"
    } else if (params.stranded && params.stranded == 'fr-secondstrand'){
        isStrandSpecific = "-s 1"
    } else {
        isStrandSpecific = ''
    }
    extraAttributes = params.extra_attributes ? "--extraAttributes ${params.extra_attributes}" : ''
    allow_multimap = params.allow_multimap ? "-M" : ''
    allow_overlap = params.allow_overlap ? "-O" : ''
    count_fractionally = params.count_fractionally ? "--fraction" : ''
    threads_num = params.fc_threads_num > 0 ? "-T ${params.fc_threads_num}" : ''

    """
    featureCounts -a $gtf -g ${params.group_features} -t ${params.count_type} -o ${name}_histone.featureCounts.txt  \\
    $isPairedEnd $isStrandSpecific $extraAttributes $count_fractionally $allow_multimap $allow_overlap $threads_num ${bam}
    
    """
}

process merge_featureCounts_histone {
    publishDir "${params.outdir}/merged_output_files", mode: 'copy'

    input:
    file input_files from featureCounts_to_merge_histone.collect()

    output:
    file 'merged_featureCounts_gene_histone.txt' into ch_fcounts_histone_merged

    script:
    // Redirection (the `<()`) for the win!
    // Geneid in 1st column and gene_name in 7th
    gene_ids = "<(tail -n +2 ${input_files[0]} | cut -f1,6,7 )"
    counts = input_files.collect{filename ->
      // Remove first line and take third column
      "<(tail -n +2 ${filename} | sed 's:.bam::' | cut -f8)"}.join(" ")
    """
    paste $gene_ids $counts > merged_featureCounts_gene_histone.txt
    """
  }

///////////////////////////////////////////////////////////////////////////////
/*
* STEP 10 - edgeR MDS and heatmap
*/
///////////////////////////////////////////////////////////////////////////////

process sample_correlation {
    label 'process_medium'
    publishDir "${params.outdir}/sample_correlation", mode: 'copy'

    input:
    file input_files from geneCounts.collect()
    val num_bams from ch_hisat2_bamcount.count()
    file mdsplot_header from ch_mdsplot_header
    file heatmap_header from ch_heatmap_header

    output:
    file "*.{txt,pdf,csv}" into sample_correlation_results

    when:
    num_bams > 2 && (!params.sampleLevel)

    script:
    """
    edgeR_heatmap_MDS.r $input_files
    cat $mdsplot_header edgeR_MDS_Aplot_coordinates_mqc.csv >> tmp_file
    mv tmp_file edgeR_MDS_Aplot_coordinates_mqc.csv
    cat $heatmap_header log2CPM_sample_correlation_mqc.csv >> tmp_file
    mv tmp_file log2CPM_sample_correlation_mqc.csv
    """

}

///////////////////////////////////////////////////////////////////////////////
/*
* STEP 11 - ERCC corr barplot
*/
///////////////////////////////////////////////////////////////////////////////

process ercc_correlation {
    label 'process_low'
    
    publishDir "${params.outdir}/", mode: 'copy',
        saveAs: {filename ->
            filename.indexOf(".txt") > 0 ? "merged_output_files/$filename" : "ercc_correlation/$filename"
            }

    when:
    ercc_list.val.size()>0 && (params.spike_in_ercc || params.spike_in_sirv)

    input:
    val ercc_input_amount from ch_spike_in_ercc
    file ercc_count from ercccount_merged
    file ercc_data from ch_ercc_data
    file ercc_header from ch_ercc_corr_header

    output:
    file "*.{txt,pdf,csv}" into ercc_correlation_results

    script:
    """
    drawplot_ERCC_corr.r $ercc_count $ercc_data $ercc_input_amount
    cat $ercc_header ercc_counts_copynum_correlation.csv >> tmp_file
    mv tmp_file ercc_counts_copynum_correlation_mqc.csv
    """

}

///////////////////////////////////////////////////////////////////////////////
/*
* STEP 12 - assigned to genome rate barplot
*/
///////////////////////////////////////////////////////////////////////////////

process create_plots_assignedgenome {
    label 'process_low'
    publishDir "${params.outdir}/plots_bar_assignedgenome", mode: 'copy'

    input:
    file totalseq_merged from ch_totalseq_assignedgenome
    file totalread_merged from ch_totalread_merged
    file assignedgenome_header from ch_assignedgenome_header

    output:
    file "*.{txt,pdf,csv}" into assignedgenome_rate_results

    script:
    isPairedEnd = params.single_end ? "False" : "True"
    """
    drawplot_assignedgenomerate_bar.r $totalseq_merged $totalread_merged $isPairedEnd
    cat $assignedgenome_header barplot_assignedgenome_rate.csv >> tmp_file
    mv tmp_file barplot_assignedgenome_rate_mqc.csv
    """

}

///////////////////////////////////////////////////////////////////////////////
/*
* STEP 13 - featureCounts mapped rate barplot
*/
///////////////////////////////////////////////////////////////////////////////

process create_plots_fcounts_allgene {
    label 'process_low'
    publishDir "${params.outdir}/plots_bar_fcounts_allgene", mode: 'copy'

    input:
    file totalseq_merged from ch_totalseq_fcount_allgene
    file allgene_merged from ch_fcounts_allgene_merged
    file fcounts_allgene_header from ch_fcounts_allgene_header

    output:
    file "*.{txt,pdf,csv}" into fcounts_allgene_results

    script:
    isPairedEnd = params.single_end ? "False" : "True"
    annotation_name = "allgene"
    """
    drawplot_fcount_mappedrate_bar.r $totalseq_merged $allgene_merged $isPairedEnd $annotation_name
    cat $fcounts_allgene_header barplot_assignedrate_allgene.csv >> tmp_file
    mv tmp_file barplot_assignedrate_allgene_mqc.csv
    """

}

process create_plots_fcounts_mt {
    label 'process_low'
    publishDir "${params.outdir}/plots_bar_fcounts_mt", mode: 'copy'

    input:
    file totalseq_merged from ch_totalseq_fcount_allgene
    file mt_merged from ch_fcounts_mt_merged
    file fcounts_mt_header from ch_fcounts_mt_header

    output:
    file "*.{txt,pdf,csv}" into fcounts_mt_results

    script:
    isPairedEnd = params.single_end ? "False" : "True"
    annotation_name = "mitochondrial"
    """
    drawplot_fcount_mappedrate_bar.r $totalseq_merged $mt_merged $isPairedEnd $annotation_name
    cat $fcounts_mt_header barplot_assignedrate_mitochondrial.csv >> tmp_file
    mv tmp_file barplot_assignedrate_mitochondrial_mqc.csv
    """

}

process create_plots_fcounts_rrna {
    label 'process_low'
    publishDir "${params.outdir}/plots_bar_fcounts_rrna", mode: 'copy'

    input:
    file totalseq_merged from ch_totalseq_fcount_allgene
    file rrna_merged from ch_fcounts_rrna_merged
    file fcounts_rrna_header from ch_fcounts_rrna_header

    output:
    file "*.{txt,pdf,csv}" into fcounts_rrna_results

    script:
    isPairedEnd = params.single_end ? "False" : "True"
    annotation_name = "rrna"
    """
    drawplot_fcount_mappedrate_bar.r $totalseq_merged $rrna_merged $isPairedEnd $annotation_name
    cat $fcounts_rrna_header barplot_assignedrate_rrna.csv >> tmp_file
    mv tmp_file barplot_assignedrate_rrna_mqc.csv
    """

}


process create_plots_fcounts_histone {
    label 'process_low'
    publishDir "${params.outdir}/plots_bar_fcounts_histone", mode: 'copy'

    input:
    file totalseq_merged from ch_totalseq_fcount_allgene
    file histone_merged from ch_fcounts_histone_merged
    file fcounts_histone_header from ch_fcounts_histone_header

    output:
    file "*.{txt,pdf,csv}" into fcounts_histone_results

    script:
    isPairedEnd = params.single_end ? "False" : "True"
    annotation_name = "histone"
    """
    drawplot_fcount_mappedrate_bar.r $totalseq_merged $histone_merged $isPairedEnd $annotation_name
    cat $fcounts_histone_header barplot_assignedrate_histone.csv >> tmp_file
    mv tmp_file barplot_assignedrate_histone_mqc.csv
    """

}

///////////////////////////////////////////////////////////////////////////////
/*
* STEP 14 - create plot from TPM counts
*/
///////////////////////////////////////////////////////////////////////////////

process create_plots_fromTPM {
    label 'process_medium'
    publishDir "${params.outdir}/plots_from_tpmcounts", mode: 'copy'

    input:
    file tpm_count from tpmcount_plot
    file detgene_header from ch_num_of_detgene_header
    file pcaplot_header from ch_pcaplot_header
    file tsneplot_header from ch_tsneplot_header
    file umapplot_header from ch_umapplot_header

    output:
    file "*.{txt,pdf,csv}" into plots_from_tpmcounts_results

    script:
    """
    drawplot_tpm_counts.r $tpm_count fcounts
    cat $detgene_header barplot_num_of_detectedgene.csv >> tmp_file
    mv tmp_file barplot_num_of_detectedgene_mqc.csv
    
    if [[ -f pcaplot_tpm_allsample.csv ]]; then
        cat $pcaplot_header pcaplot_tpm_allsample.csv >> tmp_file
        mv tmp_file pcaplot_tpm_allsample_mqc.csv
    fi
    
    if [[ -f tsneplot_tpm_allsample.csv ]]; then
        cat $tsneplot_header tsneplot_tpm_allsample.csv >> tmp_file
        mv tmp_file tsneplot_tpm_allsample_mqc.csv
    fi

    if [[ -f umapplot_tpm_allsample.csv ]]; then
        cat $umapplot_header umapplot_tpm_allsample.csv >> tmp_file
        mv tmp_file umapplot_tpm_allsample_mqc.csv
    fi
    
    """

}




///////////////////////////////////////////////////////////////////////////////
/*
* STEP X - MultiQC
*/
///////////////////////////////////////////////////////////////////////////////

process multiqc {
    label 'process_low'
    publishDir "${params.outdir}/MultiQC", mode: 'copy'
    container "ewels/multiqc:1.9"

    input:
    file (multiqc_config) from ch_multiqc_config
    file (mqc_custom_config) from ch_multiqc_custom_config.collect().ifEmpty([])
    file ('fastqc/*') from ch_fastqc_results.collect().ifEmpty([])
    file ('fastqc/*') from ch_trimmed_reads_fastqc_results.collect().ifEmpty([])
    file ('alignment/*') from ch_alignment_logs.collect().ifEmpty([])
    file ('rseqc/*') from rseqc_results_merge.collect().ifEmpty([])
    file ('featureCounts_biotype/*') from featureCounts_biotype.collect()
    file ('rsem_bowtie2_allgenes/*') from rsem_results_genes_stat.collect().ifEmpty([])
    file ('sample_correlation_results/*') from sample_correlation_results.collect().ifEmpty([]) // If the Edge-R is not run create an Empty array
    file ('ercc_correlation_results/*') from ercc_correlation_results.collect().ifEmpty([]) 
    file ('plots_bar_assignedgenome/*') from assignedgenome_rate_results.collect().ifEmpty([]) 
    file ('plots_bar_fcounts_allgene/*') from fcounts_allgene_results.collect().ifEmpty([]) 
    file ('plots_bar_fcounts_mt/*') from fcounts_mt_results.collect().ifEmpty([]) 
    file ('plots_bar_fcounts_rrna/*') from fcounts_rrna_results.collect().ifEmpty([]) 
    file ('plots_bar_fcounts_histone/*') from fcounts_histone_results.collect().ifEmpty([]) 
    file ('plots_from_tpmcounts/*') from plots_from_tpmcounts_results.collect().ifEmpty([])
    file ('plots_from_tpmcounts_rsem/*') from plots_from_rsem_gene_results.collect().ifEmpty([])
    file ('plots_from_tpmcounts_rsem/*') from plots_from_rsem_ts_results.collect().ifEmpty([])
    file ('software_versions/*') from ch_software_versions_yaml.collect()
    file workflow_summary from ch_workflow_summary.collectFile(name: "workflow_summary_mqc.yaml")

    output:
    file "*multiqc_report.html" into ch_multiqc_report
    file "*_data"
    file "multiqc_plots"

    script:
    rtitle = custom_runName ? "--title \"$custom_runName\"" : ''
    rfilename = custom_runName ? "--filename " + custom_runName.replaceAll('\\W','_').replaceAll('_+','_') + "_multiqc_report" : ''
    custom_config_file = params.multiqc_config ? "--config $mqc_custom_config" : ''
    // TODO: Specify which MultiQC modules to use with -m for a faster run time
    """
    multiqc -f $rtitle $rfilename $custom_config_file .
    """
}

///////////////////////////////////////////////////////////////////////////////
/*
* STEP X - Output Description HTML
*/
///////////////////////////////////////////////////////////////////////////////

process output_documentation {
    publishDir "${params.outdir}/pipeline_info", mode: 'copy'

    input:
    file output_docs from ch_output_docs

    output:
    file "results_description.html"

    script:
    """
    markdown_to_html.py $output_docs -o results_description.html
    """
}

///////////////////////////////////////////////////////////////////////////////
/*
* Completion e-mail notification
*/
///////////////////////////////////////////////////////////////////////////////

workflow.onComplete {

    // Set up the e-mail variables
    def subject = "[ramdaq] Successful: " + workflow.runName
    if (!workflow.success) {
        subject = "[ramdaq] FAILED: " + workflow.runName
    }
    def email_fields = [:]
    email_fields['version'] = workflow.manifest.version
    email_fields['runName'] = custom_runName ?: workflow.runName
    email_fields['success'] = workflow.success
    email_fields['dateComplete'] = workflow.complete
    email_fields['duration'] = workflow.duration
    email_fields['exitStatus'] = workflow.exitStatus
    email_fields['errorMessage'] = (workflow.errorMessage ?: 'None')
    email_fields['errorReport'] = (workflow.errorReport ?: 'None')
    email_fields['commandLine'] = workflow.commandLine
    email_fields['projectDir'] = workflow.projectDir
    email_fields['summary'] = summary
    email_fields['summary']['Date Started'] = workflow.start
    email_fields['summary']['Date Completed'] = workflow.complete
    email_fields['summary']['Pipeline script file path'] = workflow.scriptFile
    email_fields['summary']['Pipeline script hash ID'] = workflow.scriptId
    if (workflow.repository) email_fields['summary']['Pipeline repository Git URL'] = workflow.repository
    if (workflow.commitId) email_fields['summary']['Pipeline repository Git Commit'] = workflow.commitId
    if (workflow.revision) email_fields['summary']['Pipeline Git branch/tag'] = workflow.revision
    email_fields['summary']['Nextflow Version'] = workflow.nextflow.version
    email_fields['summary']['Nextflow Build'] = workflow.nextflow.build
    email_fields['summary']['Nextflow Compile Timestamp'] = workflow.nextflow.timestamp

    // On success try attach the multiqc report
    def mqc_report = null
    try {
        if (workflow.success) {
            mqc_report = ch_multiqc_report.getVal()
            if (mqc_report.getClass() == ArrayList) {
                log.warn "[ramdaq] Found multiple reports from process 'multiqc', will use only one"
                mqc_report = mqc_report[0]
            }
        }
    } catch (all) {
        log.warn "[ramdaq] Could not attach MultiQC report to summary email"
    }

    // Check if we are only sending emails on failure
    email_address = params.email
    if (!params.email && params.email_on_fail && !workflow.success) {
        email_address = params.email_on_fail
    }

    // Render the TXT template
    def engine = new groovy.text.GStringTemplateEngine()
    def tf = new File("$baseDir/assets/email_template.txt")
    def txt_template = engine.createTemplate(tf).make(email_fields)
    def email_txt = txt_template.toString()

    // Render the HTML template
    def hf = new File("$baseDir/assets/email_template.html")
    def html_template = engine.createTemplate(hf).make(email_fields)
    def email_html = html_template.toString()

    // Render the sendmail template
    def smail_fields = [ email: email_address, subject: subject, email_txt: email_txt, email_html: email_html, baseDir: "$baseDir", mqcFile: mqc_report, mqcMaxSize: params.max_multiqc_email_size.toBytes() ]
    def sf = new File("$baseDir/assets/sendmail_template.txt")
    def sendmail_template = engine.createTemplate(sf).make(smail_fields)
    def sendmail_html = sendmail_template.toString()

    // Send the HTML e-mail
    if (email_address) {
        try {
            if (params.plaintext_email) { throw GroovyException('Send plaintext e-mail, not HTML') }
            // Try to send HTML e-mail using sendmail
            [ 'sendmail', '-t' ].execute() << sendmail_html
            log.info "[ramdaq] Sent summary e-mail to $email_address (sendmail)"
        } catch (all) {
            // Catch failures and try with plaintext
            [ 'mail', '-s', subject, email_address ].execute() << email_txt
            log.info "[ramdaq] Sent summary e-mail to $email_address (mail)"
        }
    }

    // Write summary e-mail HTML to a file
    def output_d = new File("${params.outdir}/pipeline_info/")
    if (!output_d.exists()) {
        output_d.mkdirs()
    }
    def output_hf = new File(output_d, "pipeline_report.html")
    output_hf.withWriter { w -> w << email_html }
    def output_tf = new File(output_d, "pipeline_report.txt")
    output_tf.withWriter { w -> w << email_txt }

    c_green = params.monochrome_logs ? '' : "\033[0;32m";
    c_purple = params.monochrome_logs ? '' : "\033[0;35m";
    c_red = params.monochrome_logs ? '' : "\033[0;31m";
    c_reset = params.monochrome_logs ? '' : "\033[0m";

    if (workflow.stats.ignoredCount > 0 && workflow.success) {
        log.info "-${c_purple}Warning, pipeline completed, but with errored process(es) ${c_reset}-"
        log.info "-${c_red}Number of ignored errored process(es) : ${workflow.stats.ignoredCount} ${c_reset}-"
        log.info "-${c_green}Number of successfully ran process(es) : ${workflow.stats.succeedCount} ${c_reset}-"
    }

    if (workflow.success) {
        log.info "-${c_purple}[ramdaq]${c_green} Pipeline completed successfully${c_reset}-"
    } else {
        checkHostname()
        log.info "-${c_purple}[ramdaq]${c_red} Pipeline completed with errors${c_reset}-"
    }
    
    // copy .nextflow.log
    today = new Date().format("yyyy-MM-dd-HH-mm-ss")
    new File("${params.outdir}/ramdaq-${today}.log") << new File('.nextflow.log').text
    
    println "The log file .nextflow.log was copied to ${params.outdir}/ramdaq-${today}.log"
}

def nfcoreHeader() {
    // Log colors ANSI codes
    c_black = params.monochrome_logs ? '' : "\033[0;30m";
    c_blue = params.monochrome_logs ? '' : "\033[0;34m";
    c_cyan = params.monochrome_logs ? '' : "\033[0;36m";
    c_dim = params.monochrome_logs ? '' : "\033[2m";
    c_green = params.monochrome_logs ? '' : "\033[0;32m";
    c_purple = params.monochrome_logs ? '' : "\033[0;35m";
    c_reset = params.monochrome_logs ? '' : "\033[0m";
    c_white = params.monochrome_logs ? '' : "\033[0;37m";
    c_yellow = params.monochrome_logs ? '' : "\033[0;33m";

    return """    ----------------------------------------------------
            ramdaq v${workflow.manifest.version}
    ----------------------------------------------------
    """.stripIndent()
}

def checkHostname() {
    def c_reset = params.monochrome_logs ? '' : "\033[0m"
    def c_white = params.monochrome_logs ? '' : "\033[0;37m"
    def c_red = params.monochrome_logs ? '' : "\033[1;91m"
    def c_yellow_bold = params.monochrome_logs ? '' : "\033[1;93m"
    if (params.hostnames) {
        def hostname = "hostname".execute().text.trim()
        params.hostnames.each { prof, hnames ->
            hnames.each { hname ->
                if (hostname.contains(hname) && !workflow.profile.contains(prof)) {
                    log.error "====================================================\n" +
                            "  ${c_red}WARNING!${c_reset} You are running with `-profile $workflow.profile`\n" +
                            "  but your machine hostname is ${c_white}'$hostname'${c_reset}\n" +
                            "  ${c_yellow_bold}It's highly recommended that you use `-profile $prof${c_reset}`\n" +
                            "============================================================"
                }
            }
        }
    }
}
