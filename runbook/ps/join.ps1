$c = New-Object PSCredential('__NETBIOS__\Administrator', (ConvertTo-SecureString '{{ADMIN_PASSWORD}}' -AsPlainText -Force))
Resolve-DnsName __DOMAIN__ -ErrorAction Stop | Out-Null    # fails here if DNS/IPv6 is wrong
Add-Computer -DomainName __DOMAIN__ -Credential $c -Force
'joined'
