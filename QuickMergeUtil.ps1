# this script is intended with a 'MergePaths.txt' alongside it. 
# The text file should define directories or files to merge
# these should map 1 to 1 from the source to the target.
param(
  [Parameter(Mandatory = $false)]
  [string] $source_stream,

  [Parameter(Mandatory = $false)]
  [string] $source_project,

  [Parameter(Mandatory = $false)]
  [string] $target_workspace,

  [Parameter(Mandatory = $false)]
  [string] $target_project,

  [Parameter(Mandatory = $false)]
  [string] $merge_paths_file_name
)

if (-not $source_stream) {
  Write-Host "`nEnter Source stream:"
  $source_stream = Read-Host
}

$source_stream = $source_stream.TrimEnd('/')

# Check if the stream exists
$stream_listing = (p4 -z tag streams -T Stream | Select-String -Pattern "^... Stream $source_stream")
if (-not $stream_listing) {
  Write-Host "Error: Specified source stream does not exist. Exiting."
  Read-Host
  exit
}

if (-not $source_project) {
  # default project to stream depot name
  $stream_parts = $source_stream.Split("/", [System.StringSplitOptions]::RemoveEmptyEntries)
  $source_project = ($stream_parts[0..($stream_parts.Length - 2)] -join '/')

  Write-Host "`nEnter Source project (leave empty to use default '$source_project')"
  $override_source_project = Read-Host
  if (-not [string]::IsNullOrWhiteSpace($override_source_project)) {
    $source_project = $override_source_project
  }
}

if (-not $target_workspace) {
  Write-Host "`nEnter Target Workspace:"
  $target_workspace = Read-Host
}

# Check if the workspace exists
$workspace_listing = (p4 clients -e $target_workspace | Select-String -Pattern "Client $target_workspace")
if (-not $workspace_listing) {
  Write-Host "Error: Specified workspace does not exist. Exiting."
  Read-Host
  exit
}

# fetch client info
$workspace_info = p4 -z tag client -o $target_workspace
$workspace_stream_parts = ($workspace_info | Select-String -Pattern "^... Stream").Line.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)

$target_stream = $workspace_stream_parts[2]

if (-not $target_project) {
  # default project to stream depot name
  $target_stream_parts = $target_stream.Split("/", [System.StringSplitOptions]::RemoveEmptyEntries)
  $target_project = ($target_stream_parts[0..($target_stream_parts.Length - 2)] -join '/')

  Write-Host "`nEnter Target project (leave empty to use default '$target_project')"
  $override_target_project = Read-Host
  if (-not [string]::IsNullOrWhiteSpace($override_target_project)) {
    $target_project = $override_target_project
  }
}

# confirm details with user
Write-Host "`nConfirm details`ntarget workspace: '$target_workspace'`ntarget stream: '$target_stream'`ntarget project: '$target_project'`nsource stream: '$source_stream'`nsource project: '$source_project'`n(y/n)"
$confirmation = Read-Host
if ($confirmation -ne "y") {
  Write-Host "Error: Source and Destination not confirmed. Exiting."
  Read-Host
  exit
}

# Read merge paths from file and replace variables
if (-not $merge_paths_file_name) {
  $merge_paths_file_name = "MergePaths.txt"
}

$merge_paths = Get-Content -Path "$PSScriptRoot\$merge_paths_file_name"
$source_paths = @()
$target_paths = @()

foreach ($path in $merge_paths) {
  # Ignore paths that start with :: or are empty
  if ($path.StartsWith("::") -or [string]::IsNullOrWhiteSpace($path)) {
    continue
  }

  # clean up & add source path
  $source_path = $path -replace "%project%", $source_project
  $source_paths += "$source_stream/$source_path"

  # clean up target path
  $target_path = $path -replace "%project%", $target_project
  $target_paths += "$target_stream/$target_path"
}

# Create a new changelist
$changelist_description = "Merging`n"
foreach ($i in 0..($source_paths.Count - 1)) {
  $changelist_description += "$($source_paths[$i]) to $($target_paths[$i])`n"
}

Write-Host "`nCreating changelist:`n$changelist_description`n`n"

$changelist_output = p4 -c $target_workspace --field "Description=$changelist_description" change -o | p4 -c $target_workspace change -i

if ($changelist_output) {
  $parts = $changelist_output -split " "
  $changelist_number = $parts[1]
  if ($changelist_number -match '^\d+$') {
    Write-Host "Changelist $changelist_number Created!"
  } else {
    Write-Host "Failed to create changelist."
    exit
}
}

# Run the integrate command
Write-Host "`nIntegrating files..."
$integrate_command_prefix = "p4 -c $target_workspace integrate -F -c $changelist_number"
foreach ($i in 0..($source_paths.Count - 1)) {
  $source_path = $source_paths[$i]
  $target_path = $target_paths[$i]
  $integrate_command = "$integrate_command_prefix $source_path $target_path"
  Write-Host "- Integrating '$source_path' to '$target_path' ..."
  Invoke-Expression $integrate_command | Out-Null
}

# resolve integration
Write-Host "`nMerging integrated files..."
Invoke-Expression "p4 -c $target_workspace resolve -am -c $changelist_number" | Out-Null

# Output workspace name and changelist number
Write-Host "`nMerge completed to $target_workspace with changelist $changelist_number"
Read-Host