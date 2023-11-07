###############################################################################################
### This script was written by Joshua Hooks (jphooks@gmail.com)                             ###
### It's purpose is to get a list of all applications and packages from SCCM                ###
### It then checks to determine if they're on any active/live task sequences or deployments ###
### It outputs 2 CSV files that help guide you into what can be deleted to clean up space   ###
### A text file is also outputted with the source paths to be used in another script to     ###
### find orphanded folders not attached to any applications/packages that can be deleted    ###
### Nothing is deleted by this script, it is only a report to help a human decide what can  ###
### be removed safely.  Just set your two variables and go!                                 ###
###############################################################################################

# Variables to set (SCCM Site Code and FQDN of SCCM Server
$SiteCode = "XXX"
$SiteServer = "XXX.domain.com"

# Import the ConfigurationManager.psd1 module (Must have SCCM Console installed)
Write-Host "Importing SCCM module and setting location..." -ForegroundColor Yellow
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1"
}

# Connect to the site's drive 
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $SiteServer
    }
Set-Location "$($SiteCode):\"

# Get All Deployments
Write-Host "Getting all deployments..." -ForegroundColor Yellow
$Deployments = Get-CMDeployment

# Get All Task Sequences (If you do the fast flag, you won't get the references which are necessary)
Write-Host "Getting all task sequences..." -ForegroundColor Yellow
$CMPSSuppressFastNotUsedCheck = $true
$AllTaskSequences = Get-CMTaskSequence

# Go through the Task Sequences and build an easily referencable array removing garbage
Write-Host "Organizing task sequence array..." -ForegroundColor Yellow
$TaskSequences = foreach ($TS in $AllTaskSequences){
    if ($TS.PackageID -in $Deployments.PackageID){
        $TS_Live = $true
        }
    else{
        $TS_Live = $false
        }

    [Pscustomobject]@{
	    Name  = $TS.Name
	    Description  = $TS.LocalizedDescription
        BootImageID  = $TS.BootImageID
        PackageID  = $TS.PackageID
        SourceDate  = $TS.SourceDate
        LastRefreshTime  = $TS.LastRefreshTime
        References = $TS.References.Package
        Live = $TS_Live
        }
    }

# Get applications from server (If you do the fast flag, you don't get the XML with deployment type information which has source information)  Hascontent filters out apps with no source files.
Write-Host "Getting all applications..." -ForegroundColor Yellow
$AllApplications = Get-CMApplication | ? {$_.HasContent}

# Go through each application and built a new array of objects with deployment types, source folders, and whether they're in use or not
Write-Host "Organizing applications array..." -ForegroundColor Yellow
$Applications = ForEach ($App in $AllApplications){ 
    
    # Get Task Sequence Info
    $TSCount = 0
    $TSName = $TSCreateDate = $TSModDate = $TSActive = $TSLive = @()
    foreach ($TS in $TaskSequences){
        if ($App.ModelName -in $TS.References){
            $TSCount++
            $TSName += $TS.Name
            $TSCreateDate += $TS.SourceDate
            $TSModDate += $TS.LastRefreshTime
            if ($TSCreateDate -ge (Get-Date).AddDays(-90) -or $TSModDate -ge (Get-Date).AddDays(-90)){
                $TSActive += $true
                }
            else{
                $TSActive += $false
                }
            if ($TS.Live){
                $TSLive += $true
                }
            else{
                $TSLive += $false
                }
            }
        }

    # Get Deployment Info
    $DPCount = 0
    $DPName = $DPCreateDate = $DPModDate = $DPActive = @()
    foreach ($DP in $Deployments){
        if ($App.ModelName -in $DP.ModelName){
            $DPCount++
            $DPName += $DP.SoftwareName
            $DPCreateDate += $DP.CreationTime
            $DPModDate += $DP.ModificationTime
             if ($DPCreateDate -ge (Get-Date).AddDays(-90) -or $DPModDate -ge (Get-Date).AddDays(-90)){
                $DPActive += $true
                }
            else{
                $DPActive += $false
                }
            }
        }

    # Build a Notes field
    if ($app.DateCreated -ge (Get-Date).AddDays(-90) -or $app.DateLastModified -ge (Get-Date).AddDays(-90) -or $DPActive -contains $true -or $DPActive -eq $true -or $TSActive -contains $true -or $TSActive -eq $true -or $TSLive -contains $true -or $TSLive -eq $true){
        $notes = "Not safe to delete. "
        $deletemeapp = $false
        }
    else{
        $notes = "Probably safe to delete. "
        $deletemeapp = $true
        }

    if ($app.DateCreated -ge (Get-Date).AddDays(-90)){
        $notes += "App created recently. "
        }

    if ($app.DateLastModified -ge (Get-Date).AddDays(-90)){
        $notes += "App modified recently."
        }
    
    if ($DPActive -contains $true -or $DPActive -eq $true){
        $notes += "Active Deployment. "
        }
    elseif ($DPActive -contains $false -or $DPActive -eq $false){
        $notes += "InActive Deployment. "
        }

    if ($TSLive -contains $true -or $TSLive -eq $true){
        $notes += "Live Task Sequence. "
        }
    
    if ($TSActive -contains $true -or $TSActive -eq $true){
        $notes += "Active Task Sequence. "
        }
    elseif ($TSActive -contains $false -or $TSActive -eq $false){
        $notes += "Inactive Task Sequence. "
        }

    # Go through each deployment type and create a new object with everything useful
    # Note - I commented out a bunch b/c the CSV was very noisy
    $PackageXml = [xml]$App.SDMPackageXML
    ForEach($DT in @($PackageXml.AppMgmtDigest.DeploymentType)) {
        [Pscustomobject]@{
	        Notes = $notes
            DT_Source  = $DT.Installer.Contents.Content.Location
            DT_Size_MB = ([Math]::Round((($DT.Installer.Contents.Content.File.Size | Measure-Object -Sum).Sum / 1024 /1024),2))
            AppName  = $app.LocalizedDisplayName
	        CI_UniqueID  = $app.CI_UniqueID
            #Description  = $app.LocalizedDescription
	        CreatedBy  = $app.CreatedBy
	        LastModifiedBy  = $app.LastModifiedBy
            Deployed = $app.IsDeployed
            DPCount = $DPCount
            #DPName = $DPName -join ', '
            #DPCreateDate = $DPCreateDate -join ', '
            #DPModDate = $DPModDate -join ', '
            #DPActive = $DPActive -join ', '
	        TSCount = $TSCount
            #TSName = $TSName -join ', '
            #TSCreateDate = $TSCreateDate -join ', '
            #TSModDate = $TSModDate -join ', '
            #TSActive = $TSActive -join ', '
            #CI_ID  = $app.CI_ID
	        #DateCreated  = $app.DateCreated
	        #DateLastModified  = $app.DateLastModified
	        #NumberOfDeployments  = $app.NumberOfDeployments
            #HasContent  = $app.HasContent
            DT_Count  = $app.NumberOfDeploymentTypes
	        DT_Title  = $DT.Title.'#text'
	        DT_Tech = $DT.Technology
            DeleteMe = $deletemeapp
	        }
        }
    }

# Sort by the notes and content size
$Applications = $Applications | Sort DeleteMe, DT_Size_MB -desc 

# Get all packages from server
Write-Host "Getting all programs..." -ForegroundColor Yellow
$AllPackages = @()
$AllPackages += Get-CMPackage -Fast -PackageType RegularPackage
$AllPackages += Get-CMPackage -Fast -PackageType Driver
$AllPackages += Get-CMPackage -Fast -PackageType ImageDeployment
$AllPackages += Get-CMPackage -Fast -PackageType BootImage

# Go through the packages to build a CSV
Write-Host "Organizing programs array..." -ForegroundColor Yellow
$Packages = foreach ($Package in $AllPackages){
    # Get Task Sequence Info
    $TSCount = 0
    $TSName = $TSCreateDate = $TSModDate = $TSActive = $TSLive = @()
    foreach ($TS in $TaskSequences){
        if ($Package.PackageID -in $TS.References){
            $TSCount++
            $TSName += $TS.Name
            $TSCreateDate += $TS.SourceDate
            $TSModDate += $TS.LastRefreshTime
            if ($TSCreateDate -ge (Get-Date).AddDays(-90) -or $TSModDate -ge (Get-Date).AddDays(-90)){
                $TSActive += $true
                }
            else{
                $TSActive += $false
                }
            if ($TS.Live){
                $TSLive += $true
                }
            else{
                $TSLive += $false
                }
            }
        }

    # Get Deployment Info
    $DPCount = 0
    $DPName = $DPCreateDate = $DPModDate = $DPActive = @()
    $DeployedTF = $False
    foreach ($DP in $Deployments){
        if ($Package.PackageID -in $DP.PackageID){
            $DeployedTF = $true
            $DPCount++
            $DPName += $DP.SoftwareName
            $DPCreateDate += $DP.CreationTime
            $DPModDate += $DP.ModificationTime
             if ($DPCreateDate -ge (Get-Date).AddDays(-90) -or $DPModDate -ge (Get-Date).AddDays(-90)){
                $DPActive += $true
                }
            else{
                $DPActive += $false
                }
            }
        }

    # Build a Notes field
    if ($Package.SourceDate -ge (Get-Date).AddDays(-90) -or $Package.LastRefreshTime -ge (Get-Date).AddDays(-90) -or $DPActive -contains $true -or $DPActive -eq $true -or $TSActive -contains $true -or $TSActive -eq $true -or $TSLive -contains $true -or $TSLive -eq $true){
        $notes = "Not safe to delete. "
        $deletemepkg = $false
        }
    else{
        $notes = "Probably safe to delete. "
        $deletemepkg = $true
        }

    if ($Package.SourceDate -ge (Get-Date).AddDays(-90)){
        $notes += "Package created recently. "
        }

    if ($Package.LastRefreshTime -ge (Get-Date).AddDays(-90)){
        $notes += "Package modified recently."
        }
    
    if ($DPActive -contains $true -or $DPActive -eq $true){
        $notes += "Active Deployment. "
        }
    elseif ($DPActive -contains $false -or $DPActive -eq $false){
        $notes += "InActive Deployment. "
        }

    if ($TSLive -contains $true -or $TSLive -eq $true){
        $notes += "Live Task Sequence. "
        }
    
    if ($TSActive -contains $true -or $TSActive -eq $true){
        $notes += "Active Task Sequence. "
        }
    elseif ($TSActive -contains $false -or $TSActive -eq $false){
        $notes += "Inactive Task Sequence. "
        }

    # Package Type
    Switch($Package.PackageType){
        0 {$PkgType = "Normal"}
        3 {$PkgType = "Driver"}
        257 {$PkgType = "ImageOS"}
        258 {$PkgType = "ImageBoot"}
        Default {$PkgType = $Package.PackageType}
        }

    # Build custom object for export
    [Pscustomobject]@{
	    Notes = $notes
        PkgSource= $Package.PkgSourcePath
        PkgType = $PkgType
        PkgSizeMB = ([Math]::Round(($Package.PackageSize / 1024),1))
        PkgName  = $Package.Name
        PackageID = $Package.PackageID
        Deployed = $DeployedTF
        DPCount = $DPCount
	    TSCount = $TSCount
        SourceDate = $Package.SourceDate
        LastRefreshTime = $Package.LastRefreshTime
        DeleteMe = $deletemepkg
	    }
    }

# Sort by the notes and content size
$Packages = $Packages | sort DeleteMe, PkgSizeMB -desc

# Export to Desktop
$DesktopPath = [Environment]::GetFolderPath("Desktop")
Write-Host "Exporting application and package CSVs to $DesktopPath" -Foreground Green
$Packages | Export-CSV -NoTypeInformation "$DesktopPath\Packages.csv"
$Applications | Export-CSV -NoTypeInformation "$DesktopPath\Applications.csv"

# Export list of source directories to text to use for other scripts
Write-Host "Exporting source directory text file for use in orphaned data script" -ForegroundColor Green
$SourceFolders = $Packages.PkgSource + $Applications.DT_Source | ? {$_ -notlike ''} | Sort -Unique | Out-File "$DesktopPath\SourcePaths.txt"
