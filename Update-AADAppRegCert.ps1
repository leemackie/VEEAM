## Replace the file path with the source of your certificate and output path with the location where you want to save the thumprint details
#Get-PfxCertificate -Filepath "C:\temp\auth-veeam.cer" | Out-File -FilePath "C:\temp\auth-veeam.cer.thumbprint.txt"

# Replace the file path with the location of your certificate
$key = [convert]::ToBase64String((Get-Content C:\temp\auth-veeam.cer -Encoding byte))#  | Out-File -FilePath "C:\temp\auth-veeam.key.txt"

# Add to the Veeam App
Import-Module Microsoft.Graph.Applications

<#
$params = @{
	keyCredentials = @(
		@{
			#endDateTime = [System.DateTime]::Parse("2025-11-10T10:59:59Z")
			startDateTime = [System.DateTime]::Parse("2024-12-24T11:00:00Z")
			type = "AsymmetricX509Cert"
			usage = "Verify"
			key = [System.Text.Encoding]::ASCII.GetBytes("base64MIIDADCCAeigAwIBAgIQejfrj3S974xI//npv7hFHTANBgkqhkiG9w0BAQsFADATMREwDwYDVQQDDAgyMDIzMDExNDAeFw0yMzAxMTIwOTA4NThaFw0yNDAxMTIwOTI4NThaMBMxETAPBgNVBAMMCDIwMjMwMTE0MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAt5vEj6j1l5wOVHR4eDGe77HWslaIVJ1NqxrXPm/...+R+U7sboj+kUvmFzXI+Ge73Liu8egL2NzOHHpO43calWgq36a9YW1yhBQR1ioEchu6jmudW3rF6ktmVqQ==")
			displayName = "CN=auth-veeam.5gn.com.au"
		}
		@{
			customKeyIdentifier = [System.Text.Encoding]::ASCII.GetBytes("52ED9B5038A47B9E2E2190715CC238359D4F8F73")
			type = "AsymmetricX509Cert"
			usage = "Verify"
			key = [System.Text.Encoding]::ASCII.GetBytes("base64MIIDADCCAeigAwIBAgIQfoIvchhpToxKEPI4iMrU1TANBgkqhkiG9w0BAQsFADATMREwDwYDVQQDDAgyMDIzMDExMzAeFw0yMzAxMTIwODI3NTJaFw0yNDAxMTIwODQ3NTJaMBMxETAPBgNVBAMMCDIwMjMwMTEzMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAw+iqg1nMjYmFcFJh/.../S5X6qoEOyJBgtfpSBANWAdA==")
			displayName = "CN=20230113"
		}
	)
}

Update-MgApplication -ApplicationId $applicationId -BodyParameter $params
#>


# USE THIS TO OVERWRITE A CERT
Import-Module Microsoft.Graph.Applications

$params = @{
	keyCredentials = @(
		@{
			endDateTime = [System.DateTime]::Parse("2025-11-10T00:00:00Z")
			startDateTime = [System.DateTime]::Parse("2024-12-16T11:00:00")
			type = "AsymmetricX509Cert"
			usage = "Verify"
			key = [System.Text.Encoding]::ASCII.GetBytes("base64$key")
			displayName = "CN=20230112"
		}
	)
}

Update-MgApplication -ApplicationId $applicationId -BodyParameter $params