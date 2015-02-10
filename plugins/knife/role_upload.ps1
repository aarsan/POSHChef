<#
Copyright 2014 ASOS.com Limited

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
#>


function role_upload {


	<#

	.SYNOPSIS
		Uploads a role file to the chef server

	.DESCRIPTION
		Once a role has been created in the chef-repo it needs to be uploaded to the Chef server
		so that it can be added to the runlist of a node, another role or an environment.

		This plugin will perform the upload of the specified roles.

		Multiple files can be passed to the plugin to be uploaded.  The specified paths must be an
		absolute path to each role file.

		The name parameter can be used to specify roles that need to be uploaded.  If this is used
		then the plugin will assume that the roles are part of the chef_repo that has been specified
		and look for files that are in the <CHEF_REPO>/roles directory.  The files will have the
		.json extension added if it is not supplied

	.EXAMPLE

		PS C:\> Invoke-POSHKnife role upload -path c:\chef-repo\roles\WebServer.json

		Upload the specified file as a role to the chef server.

	.EXAMPLE

		PS C:\> Invoke-POSHKnife role upload -name WebServer

		This will result in the file <CHEF_REPO>/roles/WebServer.json being uploaded to the file
		if it exists

	#>

	param (

		[string[]]
		# Array of names of roles to be uploaded
		# these will assumed to be a the 'roles' subfolder of the chef_repo setting
		$names,

		[string[]]
		# String array of paths to the roles to upload
		$path
	)

	# Determine the name of the chef type from the function name
	$chef_type, $action = $MyInvocation.MyCommand -split "_"

	# determine the mapping for the chef query
	$mapping = "{0}s" -f $chef_type

	Write-Log -Message " "
	Write-Log -EVentId PC_INFO_0031 -extra ("Uploading", (Get-Culture).TextInfo.ToTitleCase($mapping))

	# if the names array is not empty then determine the path using the poshchef settings
	if ($names.count -gt 0) {

		# check that the chef_repo path has been setup
		if ([String]::IsNullOrEmpty($script:session.config.chef_repo)) {
			Write-Log -EventId PC_WARN_0014 -LogLevel Warn -stop
		}

		# iterate around the names that has been specified
		foreach ($name in $names) {

			# build up a path to the file
			$filepath = "{0}\roles\{1}" -f $script:session.config.chef_repo, $name

			# if the path does not have a json extension add one
			if (!$filepath.endswith(".json")) {
				$filepath += ".json"
			}

			# see if the file exists
			if (Test-Path -path $filepath) {
				$path += $filepath
			} else {
				Write-Log -EventId PC_WARN_0015 -LogLevel Warn -extra ($name, $filepath)
			}
		}
	}

	# if the path array is empty stop
	if ($path.count -eq 0) {
		return
	}

	# Get a list of the roles currently on the server
	# This so it can be determined if the role already exists and needs to be upadted (PUT) or if it is new (POST)
	$items_on_server = Invoke-ChefQuery -Path ("/{0}" -f $mapping)

	# iterate around the paths that have been passed to the function
	foreach ($p in $path) {

		# attempt to the find the file in the current path
		$item_files = @(Get-ChildItem -Path $p -Filter "*.json")

		# if some files have been found iterate around then
		if ($item_files.Count -gt 0) {

			foreach ($item_file in $item_files) {

				# get the contents of the file
				$data = Get-Content -Path $item_file.Fullname -raw

				# tuen the data into an opbject to that the name of it can be determined
				$item = $data | ConvertFrom-JSON

				Write-Log -EventId PC_MISC_0000 -extra $item.name

				# Determien if the item exists ont he server, this is to work out the method to use
				$item_exists = $items_on_server.keys | Where-Object { $_ -eq $item.name }

				# determine the method and the URI for the chef rest call
				if (![String]::IsNullOrEmpty($item_exists)) {
					$method = "PUT"
					$uri = "/{0}/{1}" -f $mapping, $item.name
					$action = "Updating"
				} else {
					$method = "POST"
					$uri = "/{0}" -f $mapping
					$action = "Adding"
				}

				Write-Log -EventId PC_INFO_0030 -extra ($action, $chef_type)

				$result = Invoke-ChefQuery -Method $method -path $uri -data $data
			}
		}
	}

}