Clear-Host

@"
GetDeviceFilteredPrinterInfo-Prompted.ps1

This script outputs printer information for all devices matching the given
N-Central filter.  The script prompts for five paramters:

N-Central server name
N-Central userid
N-Central password
N-Central filter
Output CSV filename

Created by:	Jon Czerwinski, Cohn Consulting Corporation
Date:		December 16, 2013
Version:	1.0

"@


#
# Determine where the N-Central server is
#
$serverHost = Read-Host "Enter the fqdn of the N-Central Server "


#
# Generate a pseudo-unique namespace to use with the New-WebServiceProxy and 
# associated types.
#
# By controlling the namespace, the script becomes portable and is not
# dependent upon the endpoint url the webservice is connecting.  However, this
# introduces another complexity because once the namespace is defined within a
# powershell session, it cannot be reused, nor can it be undefined.  As long as
# all the calls are made to the existing webserviceproxy, then everything would be
# OK. But, if you try to rerun the script without closing and reopening the
# powershell session, you will get an error.
#
# One way around this is to create a unique namespace each time the script is run.
# We do this by using the last 'word' of a GUID appended to our base namespace 'NAble'.
# This means our type names for parameters (such as T_KeyPair) now have a dynamic
# type.  We could pass types to each new-object call using "$NWSNameSpace.T_KeyPair",
# and I find it more readable to define our 'dynamic' types here and use the typenames
# in variables when calling New-Object.
#
$NWSNameSpace = "NAble" + ([guid]::NewGuid()).ToString().Substring(25)
$KeyPairType = "$NWSNameSpace.T_KeyPair"
$KeyValueType = "$NWSNameSpace.T_KeyValue"


#
# Create PrinterData type to hold printer name and port
#
Add-Type -TypeDefinition @"
public class PrinterData {
	public string CustomerName;
	public string ComputerName;
	public string PrinterName;
	public string PrinterPort;
	}
"@


#
# Get credentials
# We could read them as plain text and then create a SecureString from it
# By reading it as a SecureString, the password is obscured on entry
#
# We still have to extract a plain-text version of the password to pass to
# the API call.
#
$username = Read-Host "Enter N-Central user id "
$secpasswd = Read-Host "Enter password " -AsSecureString

$creds = New-Object System.Management.Automation.PSCredential ("\$username", $secpasswd)
$password = $creds.GetNetworkCredential().Password

$bindingURL = "https://" + $serverHost + "/dms/services/ServerEI?wsdl"
$nws = New-Webserviceproxy $bindingURL -credential $creds -Namespace ($NWSNameSpace)


#
# Get the filter name to use
#
Write-Host
$FilterName = (Read-Host "Enter the exact filter name ").Trim()


#
# Select the output file
#
Write-Host
$CSVFile = (Read-Host "Enter the CSV output filename ").Trim()


#
# Set up and execute the query
#
$KeyPairs = @()

$KeyPair = New-Object -TypeName $KeyValueType
$KeyPair.Key = 'TargetByFilterName'
$KeyPair.Value = $FilterName
$KeyPairs += $KeyPair

$KeyPair = New-Object -TypeName $KeyValueType
$KeyPair.Key = 'InformationCategoriesInclusion'
$KeyPair.Value = @("asset.customer", "asset.device", "asset.printer")
$KeyPairs += $KeyPair

$rc = $nws.DeviceAssetInfoExport2("0.0", $username, $password, $KeyPairs)


#
# Set up the printers array, then populate with the printer name and port
#
$Printers = @()

foreach ($device in $rc) {
	$DeviceAssetInfo = @{}
	foreach ($item in $device.Info) {$DeviceAssetInfo[$item.key] = $item.Value}
	
	$CustomerName = $DeviceAssetInfo['asset.customer.customername']
	$ComputerName = $DeviceAssetInfo['asset.device.longname']
	$index = 0
	
	While ($DeviceAssetInfo["asset.printer.name.$index"]) {
		$Printer = New-Object PrinterData
		$Printer.CustomerName = $CustomerName
		$Printer.ComputerName = $ComputerName
		$Printer.PrinterName = $DeviceAssetInfo["asset.printer.name.$index"]
		$Printer.PrinterPort = $DeviceAssetInfo["asset.printer.port.$index"]
		
		$Script:Printers += $Printer
		$index ++
		}

	If ($index -gt 0) {
		Write-Host "Found $index printers on $CustomerName - $ComputerName"
		}
	
	Remove-Variable DeviceAssetInfo
	}
	
$Printers | Export-Csv -Path $CSVFile -NoTypeInformation -Force
