<#  

.SYNOPSIS
Makes a copy of all volumes that are a member of specified FlashArray Protection Group based on most recent or specified pgroup snapshot

Disclaimer:
    The sample module and documentation are provided AS IS and are not supported by
	the author or the author's employer, unless otherwise agreed in writing. You bear
	all risk relating to the use or performance of the sample script and documentation.
	The author and the author’s employer disclaim all express or implied warranties
	(including, without limitation, any warranties of merchantability, title, infringement
	or fitness for a particular purpose). In no event shall the author, the author's employer
	or anyone else involved in the creation, production, or delivery of the scripts be liable
	for any damages whatsoever arising out of the use or performance of the sample script and
	documentation (including, without limitation, damages for loss of business profits,
	business interruption, loss of business information, or other pecuniary loss), even if
	such person has been advised of the possibility of such damages.
	
.DESCRIPTION
This script will allow you to make a copy of all volumes that are a member of specified FlashArray Protection Group,
which can be based on most recent pgroup snapshot or a specified pgroup snapshot

.EXAMPLE
.\fa-pgroup-snap-copy-interactive.ps1 -faendpoint 10.21.234.191 -ProtectionGroupName clonetestingpgroup -ProtectionGroupAndVolumeCopySuffixes "-copy1,-copy2"
Connects to array at 10.21.234.191 with specified credentials and makes volume copies from most recent snapshot of clonetestingpgroup with specified count/suffixes of -copy1 and -copy2

.\fa-pgroup-snap-copy-interactive.ps1 -faendpoint 10.21.234.191 -ProtectionGroupName clonetestingpgroup -ProtectionGroupAndVolumeCopySuffixes "-copy1,-copy2" -ProtectionGroupSnapshotName clonetestingpgroup.7
Connects to array at 10.21.234.191 with specified credentials and makes volume copies from specified 'clonetestingpgroup.7' snapshot of clonetestingpgroup with specified count/suffixes of -copy1 and -copy2
#>

[CmdletBinding(ConfirmImpact='Medium')]

	Param(
		[Parameter(Mandatory=$true)]
		[String]
		$faendpoint,
		[Parameter(Mandatory=$true)]
		[String]
		$ProtectionGroupName,
		[Parameter(Mandatory=$true)]
		[String[]]
		$ProtectionGroupAndVolumeCopySuffixes,
		[Parameter()]
		[String]
		$ProtectionGroupSnapshotName
	)

# Make sure the PureStoragePowerShellSDK2 is installed ahead of time of course
Import-Module -Name PureStoragePowerShellSDK2
$flasharray = Connect-Pfa2Array -Endpoint $faendpoint -Credential (Get-Credential -Message "Credentials for $faendpoint") -IgnoreCertificateError

# If Protection Group Snapshot Name was specified then use that, otherwise find the latest snapshot
if (!$ProtectionGroupSnapshotName) {
# Get latest Protection Group snapshot - note that this should probably be updated to allow input of a named snapshot to make it more extensible
$latestpgroupsnapshotname = (Get-Pfa2ProtectionGroupSnapshot -Array $flasharray -Limit 1 -Name $ProtectionGroupName -Destroyed:$false -Sort "created-").Name
} else {
$latestpgroupsnapshotname = $ProtectionGroupSnapshotName
}

# Get all the Volume members of the pgroup - note that this is only configured to work with pgroups with only volume members
$pgroupvolmembers = Get-Pfa2ProtectionGroupVolume -Array $flasharray -GroupName $ProtectionGroupName | Select-Object Member -ExpandProperty Member | Select-Object Name

# Translate it all so that we have the individual volume-level snapshots to work with, based on pgroup snap
$volsnapstocopy = foreach ($vol in $pgroupvolmembers) {Get-Pfa2VolumeSnapshot -Array $flasharray -Destroyed:$false -SourceName $vol.Name | Where-Object {$_.Name -match "$latestpgroupsnapshotname.*"}}

# Create the pgroup and volume copies
$ProtectionGroupAndVolumeCopySuffixes = $ProtectionGroupAndVolumeCopySuffixes -split ','
foreach ($copysuffix in $ProtectionGroupAndVolumeCopySuffixes) {
	$NewProtectionGroupCopyName = $ProtectionGroupName + $copysuffix
	New-Pfa2ProtectionGroup -Array $flasharray -Name $NewProtectionGroupCopyName -Overwrite:$False
	$volcopies = foreach ($volsnap in $volsnapstocopy) {
		$newvol = $volsnap.Source.Name + $copysuffix
		New-Pfa2Volume -Array $flasharray -Name $newvol -AddToProtectionGroupNames $NewProtectionGroupCopyName -WithDefaultProtection:$False -Overwrite:$False -SourceId $volsnap.Id
	}
}
