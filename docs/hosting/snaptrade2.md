# SnapTrade API (Snaptrade2)

This connection uses SnapTrade partner API credentials and HMAC-SHA256 request
signatures. It does not require a SnapTrade OAuth app, client secret, or token
exchange. SnapTrade API access and pricing still depend on the partner account.

In **Settings > Bank sync > SnapTrade API**, enter the existing **Client ID**,
**Consumer Key**, **User ID**, and **User Secret**, then select **Save and connect**.
The credentials must belong to the same SnapTrade application and user. Existing
brokerage connections are reused; no new SnapTrade user is registered. Select
accounts in the account setup screen before they are imported as Sure accounts.
Use **Connect brokerage** to open SnapTrade's read-only connection portal when
adding a new brokerage. Brokerage login/consent may still be required there.

Configure all three persistent `ACTIVE_RECORD_ENCRYPTION_*` keys before saving
credentials, and keep a secure backup of those keys with database backups.
Credentials are stored in the local database using Active Record encryption;
saved secrets are not returned to the settings form. Blank fields during an update
retain existing values. Client ID and User ID cannot be changed on an existing
connection. Never commit `.env.local` or credential exports.

`Provider::Snaptrade2` reuses the SnapTrade account/holding processing contract and
the existing `snaptrade_items` credential columns, so no migration is required.
It fetches all pages of account activities within the existing sync date window.
The OAuth provider remains available separately. Local account cleanup does not
delete shared partner API brokerage connections in SnapTrade, since another app
may still use them. Broker authorization removal through the explicit connection
management action remains a remote operation.

Focused checks:

```sh
DISABLE_PARALLELIZATION=true bin/rails test \
  test/models/provider/snaptrade2_test.rb \
  test/controllers/snaptrade2_items_controller_test.rb \
  test/models/provider/snaptrade_oauth_test.rb \
  test/models/provider/snaptrade_adapter_test.rb
```
