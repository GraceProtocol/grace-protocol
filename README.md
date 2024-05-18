## Grace Protocol

**Grace is an L2-first cross-margin lending protocol that fairly distributes losses if they occur, making it resilient to oracle manipulation, volatility and exploits.**

### Build
```sh
forge b
```

### Test
```sh
forge t
```

### Deploy on Base Sepolia
1. Copy the contents of `.env.example` into `.env` and fill the environment variables
2. Run the bash script below
```sh
sh sh/deploy/sepolia.sh
```

### Protocol Architecture

#### Core
The core contract is a monolithic contract that contains hook functions which are called by the following:

1. Pool contracts: The core is called by Pool contracts before deposit, withdraw, borrow and repay user operations are executed.
2. Collateral contracts: The core is called by Collateral contracts before deposit and withdraw user operations are executed.
3. Liquidators: The core is called directly by third-party liquidators in cases where a borrower is liquidatable.
4. Write-off callers: The core can be called by anyone to write-off the remaining loans of a borrower who owes more debt than they have supplied as collateral.

The core is also the main entry-point for the protocol operator (team or DAO) in order to upgrade some protocol contracts (e.g. oracle, borrowController, CollateralDeployer, PoolDeployer), to deploy new Collateral and Pool contracts, and to modify global parameters.

#### Pool
Pools are deployed for each borrowable token via the core contract only. Pool contracts are the user-facing entry-points for users looking for debt-related operations such as lending and borrowing.

The pool also charges borrowers interest based which is then transferred to the feeRecipient provided by the core. Lenders never accrued interest by the Pool.

A Pool may also write-off some of the remaining debt of a borrower when requested by the core contract. In this case, the writen-off debt is deducted proportionally from each existing Pool lender by reducing the exchange rate of the Pool share token.

#### Collateral
Collaterals are deployed for each token used as collateral via the core contract only. Collateral contracts are the user-facing entry-points for users looking for collateral-related operations such as depositing or withdrawing collateral.

Collateral contracts also charge borrowers a yearly collateral fee (similar to interest) regardless of their outstanding loans elsewhere. The balance of the Collateral contract is reduced over time on each `accrueFee` call and the fee is sent to the feeRecipient address provided by the core.

#### Oracle
The Oracle contract provides the core with prices of all collateral and pool tokens. The oracle prices collateral and pool tokens differently.

The oracle prices collateral and pool tokens separately:

In the case of collateral tokens, the oracle logs the lowest price recorded for each collateral token on each call. If the current price is lower than the recorded low, it replaces the recorded low immediately. However, if the current price is higher the recorded low, the recorded low is ramped-up over time at a rate relative to the recorded low (e.g. can only go up 10% per week).

Based on the current low and the collateral factor, the oracle then prevents the current borrowing power of the collateral from exceeding the low. The live price is dampened to a point where the borrowing power of each unit of collateral is equal to the low.

The price is then further restricted based on total collateral value cap in dollar terms. For example, if the cap of a collateral is set to $1M and the amount of deposited collateral tokens is 1000 tokens, then each token can only be priced by the oracle up to $1000/token regardless of live oracle price.

In the case of pool tokens, the oracle logs the highest price recorded for each pool token on each call. If the current price is higher than the recorded high, it replaces the recorded high immediately. However, if the current price is lower the recorded high, the recorded high is ramped-down over time at a rate relative to the recorded high (e.g. can only go down 10% per week). The high is then used as the oracle price for each pool token.

#### RateProvider

The rate provider manages the interest rate model contracts for each pool and fee rate model for each collateral. A default `rateModel` can be set for all collaterals and pools by the owner.

The rate provider does not trust external `rateModel` contracts added by the owner. An invalid, inexistent or malicious model contract added by the owner should not brick the protocol or prevent users from accessing their funds.

#### Vault
Vaults allow Pool share token holders to deposit their shares into the vault in order to earn GTR rewards. Vaults are created only by the `VaultFactory`.

#### VaultFactory
The factory is used by the owner to deploy new vaults. It is also used by the owner in order to assign different reward weights for each vault. It also a vault of vaults where it mints and distributes GTR rewards to each vault contract based on its weight relative to other vaults.

#### Reserve
The reserve acts as the `feeRecipient` of the core contract. It receives all interest and collateral fees generated by the protocol. The reserve allows each GTR holder to burn their GTR tokens and redeem them for a proportional share of each ERC20 token balance stored within it. The user is responsible for providing the addresses of each token they wish to redeem or they donate their share of any missed tokens to the rest of the GTR holders.

#### Lens
The Lens contract is only used by off-chain frontend for easy access to borrower and lender info. It is intended to be gas-inefficient.
