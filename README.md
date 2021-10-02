# blockchain-developer-bootcamp-final-project
blockchain-developer-bootcamp-final-project

A commitment system, where users can:
1. indicate a pure commitment to another address
2. indicate a commitement for an exchange of asset
3. pay commitment for an exchange of asset (eqvialent to american options)

Use Case:
1. Reserve an IDO spot etc. The counterparty has an arbitration to decide whether to forfeit your commitment, use for screening out free-riders. 
2. Block trade etc. The commitment is locked once the counterpart deposits his/her side of trade. If the trade is not settled before the expiry the commitment would be forfeited and transferred to the counterparty.
3. Financial Options, the commitment is sent to the counterparty once he/she deposits his/her side of trade. The initiator has the option to settle the trade before the specified expiry time.

Scaffolding:
---

`scaffolding.sol`
