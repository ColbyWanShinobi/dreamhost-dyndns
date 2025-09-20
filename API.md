# DreamHost DNS API Reference

## Overview

The DNS API module allows you to manage your domain's DNS records. The following operations are available:

- **List all records** (`dns-list_records`)
- **Add a record** (`dns-add_record`) 
- **Remove a record** (`dns-remove_record`)

For detailed instructions on connecting to the DreamHost API, see: [Connecting to the DreamHost API](https://help.dreamhost.com/hc/en-us/articles/4407354972692)

## Authentication

All API calls require your API key as a parameter:
```
https://api.dreamhost.com/?key=YOUR_API_KEY&cmd=COMMAND&parameters...
```

## Commands

### dns-list_records

Lists all DNS records for all domains on all accounts you have access to.

**Limitations:**
- Does not list records for registration-only domains
- Does not list records for dreamhosters.com subdomains

**Usage:**
```
https://api.dreamhost.com/?key=YOUR_API_KEY&cmd=dns-list_records
```

**Example Response:**
```
success
account_id	zone	record	type	value	comment	editable
123456	example.com	example.com	A	192.168.1.1		1
123456	example.com	www.example.com	A	192.168.1.1		1
123456	example.com	mail.example.com	MX	0 mail.example.com		0
```

### dns-add_record

Adds a new DNS record to a domain (excluding dreamhosters.com subdomains).

**Note:** After adding a record, it may take several hours to propagate online.

**Required Parameters:**
- `record` - The domain name (e.g., `example.com` or `subdomain.example.com`)
- `type` - Record type: `A`, `CNAME`, `NS`, `NAPTR`, `SRV`, `TXT`, or `AAAA`
- `value` - The DNS record's value

**Optional Parameters:**
- `comment` - Optional comment for this record

**Usage:**
```
https://api.dreamhost.com/?key=YOUR_API_KEY&cmd=dns-add_record&record=DOMAIN&type=TYPE&value=VALUE&comment=COMMENT
```

**Examples:**

Add an A record:
```
https://api.dreamhost.com/?key=YOUR_API_KEY&cmd=dns-add_record&record=example.com&type=A&value=192.168.1.1
```

Add a TXT record with comment:
```
https://api.dreamhost.com/?key=YOUR_API_KEY&cmd=dns-add_record&record=example.com&type=TXT&value=test123&comment=Testing
```

Add a CNAME record:
```
https://api.dreamhost.com/?key=YOUR_API_KEY&cmd=dns-add_record&record=www.example.com&type=CNAME&value=example.com
```

### dns-remove_record

Removes an existing DNS record from a domain. You must specify the exact same values that were used when creating the record.

**Required Parameters:**
- `record` - The domain name
- `type` - Record type
- `value` - The exact DNS record value to remove

**Usage:**
```
https://api.dreamhost.com/?key=YOUR_API_KEY&cmd=dns-remove_record&record=DOMAIN&type=TYPE&value=VALUE
```

**Examples:**

Remove an A record:
```
https://api.dreamhost.com/?key=YOUR_API_KEY&cmd=dns-remove_record&record=example.com&type=A&value=192.168.1.1
```

Remove a TXT record:
```
https://api.dreamhost.com/?key=YOUR_API_KEY&cmd=dns-remove_record&record=example.com&type=TXT&value=test123
```

## Supported Record Types

| Type | Description | Example Value |
|------|-------------|---------------|
| `A` | IPv4 address | `192.168.1.1` |
| `AAAA` | IPv6 address | `2001:db8::1` |
| `CNAME` | Canonical name | `example.com` |
| `MX` | Mail exchange | `10 mail.example.com` |
| `TXT` | Text record | `v=spf1 include:_spf.google.com ~all` |
| `SRV` | Service record | `0 5 5060 sip.example.com` |
| `NS` | Name server | `ns1.dreamhost.com` |
| `NAPTR` | Naming Authority Pointer | `100 10 "u" "E2U+sip" "!^.*$!sip:info@example.com!" .` |

## Error Handling

API responses typically start with either:
- `success` - Operation completed successfully
- `error` - Operation failed, followed by error message

**Common Error Messages:**
- `no_such_record` - Record not found for removal
- `record_already_exists_remove_first` - Record already exists, remove first
- `invalid_record_type` - Unsupported record type specified
- `no_such_zone` - Domain not found in your account

## Rate Limiting

⚠️ **Important:** DreamHost has hourly rate limits on DNS API calls. Each record creation and deletion counts toward your limit. Plan your DNS updates accordingly.

## Best Practices

1. **Always use `dns-list_records` first** to check current state
2. **Remove old records before adding new ones** to avoid duplicates
3. **Use meaningful comments** for record tracking
4. **Test with dry-run logic** before making bulk changes
5. **Implement retry logic** for transient failures
6. **Monitor your API usage** to stay within rate limits

## Security Notes

- Keep your API key secure and never commit it to public repositories
- Use minimum required permissions (only `dns-*` operations)
- Regenerate API keys periodically
- Monitor API access logs in your DreamHost panel

## References

- [DreamHost API Documentation](https://help.dreamhost.com/hc/en-us/articles/4407354972692)
- [DreamHost Panel](https://panel.dreamhost.com)
- [DNS Record Types Reference](https://en.wikipedia.org/wiki/List_of_DNS_record_types)
