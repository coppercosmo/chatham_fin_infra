# Runbook: offboard a client

1. Confirm the contractual data-return / retention requirements in writing with the engagement lead.
2. Export: storage containers and AI Search index content to the agreed location; export the
   Log Analytics data the contract requires.
3. Move the client to ring `retired` in `client.json` so no further rollouts touch it.
4. Remove resource locks (`terraform apply -var="enable_locks=false"`), then
   `terraform destroy` for the client stamp, using its own deployment identity.
5. Key Vault and Cognitive Services are soft-deleted: purge them after the retention window
   (purge protection means Key Vault can't be purged early; this is intentional).
6. Remove the client from `platform` (deletes deployment identity and federated credential),
   delete the GitHub Environment, and ask P&T to cancel the subscription and remove the groups.
7. Record the offboarding date and evidence in the client's engagement folder.
