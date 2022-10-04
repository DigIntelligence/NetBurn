# NetBurn

**CD/DVD Network Publisher Host/Client for Primera PTBurn Environments**

**NETBURN provides several enhancements to a Network Connected Primera
(PTBurn) Host:**

1.  [NETBURN provides the ability to locally cache Image and Label files
    which are maintained on network resources]{.ul}: It appears that
    PTPublisher and PTBurn DO NOT cache image files locally as they
    likely expect those files to already be stored on the Primera Host
    machine. While this is not a big deal (performance-wise) for one-off
    disc publishing, it is NOT optimal for organizations which have
    large numbers of image sources (and labels) and/or wish to maintain
    them on a centrally managed (backed up) network resource. For
    example, creating 50 copies of a disc image stored on a network
    share (mapped drive) means that image must be read 50 times across
    the network. NETBURN (when running on the Primera Host)
    automatically polls a REMOTE job submission folder to obtain job
    information, copies down (locally) the associated Image and Label
    files, and then creates an appropriate Job Request File (.JRQ) for
    PTBurn to process (locally). Additionally, the PTBurn Job Request
    File is set to automatically delete the disc/label/request files
    once the job has completed.

2.  [NETBURN runs as both a Client and a Host Process]{.ul}: The exact
    same NETBURN executable will run as both a Host (for polling
    purposes) and as a Client (for local and remote job submission).
    NETBURN determines if it is running on the Primera Host by
    determining if the PTBurnJobs submission folder exists. If the
    folder exists, NETBURN will run in "Host" mode. If the folder DOES
    NOT exist, NETBURN sets itself to operate as a Client.

3.  [NETBURN in "Host" mode]{.ul}: If NETBURN is operating in HOST mode,
    it will not only provide direct job submission (via PTBurn, but it
    will also poll the network for remotely submitted jobs in the
    background. If NETBURN finds a job which has been remotely submitted
    (via a NETBURN Client), it simply builds an appropriate Job Request
    File and copies down the associated Image and Label files so they
    can be cached for local access

4.  [NETBURN in "Client" Mode]{.ul}: If NETBURN is operating in CLIENT
    mode (not running on the Primera Host), it will provide simple
    point-and-click submission for pre-defined jobs. Just click on the
    Job and identify the number of Discs desired. NETBURN does the rest.
    The Client NETBURN builds a Job Submission file (.INI) in the
    network submission folder (with the necessary job details) and then
    the NETBURN Host (running on the Primera Host) will pick up that
    file, locally cache the Image and Label files, and then submit an
    appropriate Job Description File to PTBurn.

5.  [NETBURN provides simple point and click job submission for
    pre-defined jobs:]{.ul} The NETBURN configuration file allows for
    popular/common disc publishing jobs to be easily pre-defined. The
    NETBURN main dialog box will automatically be sized to fit "buttons"
    for all pre-defined jobs. The number of jobs which can be
    pre-defined is only limited by the amount of screen real estate
    available.

6.  [NETBURN provides Search and Submission for jobs which are NOT
    pre-defined:]{.ul} A "Search" button is provided so that any jobs
    which are NOT pre-defined. NETBURN looks for any/all ISO or GI files
    via a standard user-driven Windows File Selection Dialog Box.

7.  [NETBURN automatically associates label files by using the same file
    name and path as the Image file:]{.ul} As long as Label Files are
    maintained in the same folder, and have the same file Name, as their
    corresponding Image files, NETBURN simply changes the file extension
    to identify them (.ISO/.GI -\> .STD). This makes label/Image
    management very easy and straight-forward.

8.  [NETBURN Supports Global and Image Specific PTBurn Options:]{.ul}
    While global PTBurn options are stored in the main NETBURN
    Configuration File (NetBurn.ini), NETBURN also checks for an
    OPTIONAL configuration file which can be uniquely associated with a
    particular Image file. Just like the Label File, an optional Image
    Configuration File should have the exact same path and file name
    with the file extension being ".INI". As with the Global Options
    specified in the NETBURN Configuration File, options specified in
    the Image Configuration File should be listed under a section named
    "\[PTBurn Options\]". If an Image Specific Options File is found,
    any parameters found within will append (or override) the Global
    PTBurn Options specified in the NETBURN Configuration file.

9.  [NETBURN supports the submission of multiple disc images using a
    single "Batch Job" definition:]{.ul} By selecting an \*.NBB file
    (NetBurn Batch File), instead of a standard \*.ISO or \*.GI Image
    file, NetBurn will process that file in "Batch Mode". The NBB file
    uses a standard INI file architecture to define a collection of
    Image Files (\*.ISO or \*.GI) to be submitted as a group. Each Image
    in the group is identified by a unique "\[Section Name\]" with a
    corresponding "ImageFile=" key and value (the path to the Image File
    itself). When the NBB Batch File is selected (via a pre-defined
    Button or using the "Search" function), NetBurn will ask how many
    copies of the set should be produced.

10. [NETBURN is completely portable and does not require any
    installation process:]{.ul} The NETBURN executable and its
    corresponding INI file simply need to be copied to a Network
    Resource. This very same EXE/INI can be shared by the Primera Host
    and any Network Client which wishes to use it. Furthermore, NETBURN
    is built to allow Network Clients and Host to use COMPLETELY
    DIFFERENT drive mappings for access yet still share the same
    configuration file. NETBURN simply looks in "its own folder" for its
    corresponding configuration file (INI) and the Network Job
    Submission Folder (NetBurnJobs). Network Locations for Image/Label
    files are recorded in the INI file using UNC file names. Basically
    it's just an executable (NetBurn.exe) and a config file
    (NetBurn.ini). NETBURN will create the network submission sub-folder
    (NetBurnJobs) the first time it is executed. This is where Network
    Job Submission files will be dropped (by the Clients) and polled (by
    the Host). NETBURN also creates/maintains a running log file
    (NetBurn.log) with detailed info on client host activity (Startups,
    Submission Details, Shutdowns, Job Summaries)

11. [NETBURN is Free and Open-Source]{.ul}: NETBURN is maintained as a
    project on GitHub. It is written and compiled using only the very
    simple (yet powerful) AutoIT Language and Development GUI (also
    Free): https://www.autoitscript.com/site/autoit/
