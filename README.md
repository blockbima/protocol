# BlockBima MVP Protocol

## Overview

BlockBima is a decentralized, gas-efficient parametric insurance protocol providing climate risk coverage for underserved communities. The MVP focuses on a **single pooled smart contract** that:

1. **Aggregates capital** from Liquidity Providers (LPs) and policyholder premiums.
2. **Stores policies** as on-chain structs rather than separate contracts.
3. **Triggers batch settlements** via an off-chain oracle, minimizing gas by updating only necessary fields.
4. **Maintains a liquidity buffer** to ensure solvency.
5. **Supports emergency pause** for governance intervention.

This README covers the **contract’s purpose**, **function list**, and **user workflows**.

---

## Goals of the MVP

* **Capital Efficiency**: One pool for all policies avoids idle escrow capital.
* **Gas Optimization**: Batched operations and struct-based storage minimize on-chain writes.
* **Transparency & Simplicity**: Clear, audited code paths for deposits, policy creation, settlement, and withdrawals.
* **Modular Extendibility**: Foundation for future features (DeFi yield, DAO governance, token tradability).

---

## Smart Contract: `BlockBimaMVP.sol`

### Key Components

* **Admin & Roles**: Single `admin` address (multisig) controls critical parameters.
* **Stablecoin**: ERC-20 token used for premiums and LP deposits.
* **Capital Pool**: Tracks total funds available for claims and withdrawals.
* **LP Accounting**: `lpBalances` and `totalLPTokens` represent pool shares.
* **Policy Struct**: On-chain storage of each policy’s data:

  ```solidity
  struct Policy {
    address user;
    uint256 premium;
    uint256 maxPayout;
    uint256 startTime;
    uint256 endTime;
    uint256 payoutRatio;
    bool claimed;
    string region;
  }
  ```
* **Liquidity Buffer**: `reserveRatioBps` ensures a percentage of pool is held as collateral.
* **Emergency Pause**: `paused` flag to halt operations in crises.

### Function List

| Function                                                                            | Visibility                       | Purpose                                             | Workflow Role     |
| ----------------------------------------------------------------------------------- | -------------------------------- | --------------------------------------------------- | ----------------- |
| `constructor(IERC20 _stablecoin, address _admin)`                                   | public                           | Initializes contract with stablecoin and admin.     | Setup             |
| `pause()`                                                                           | external onlyAdmin               | Pauses protocol operations.                         | Governance        |
| `unpause()`                                                                         | external onlyAdmin               | Unpauses protocol.                                  | Governance        |
| `setReserveRatio(uint16 newRatioBps)`                                               | external onlyAdmin               | Adjusts the liquidity buffer ratio.                 | Governance        |
| `depositLP(uint256 amount)`                                                         | external whenNotPaused           | LP deposits funds, mints LP tokens proportionally.  | LP Onboarding     |
| `createPolicy(uint256 premium, uint256 maxPayout, uint256 duration, string region)` | external whenNotPaused           | Policyholder purchases cover, stores policy struct. | Policy Purchase   |
| `settlePolicies(uint256[] policyIds, uint16 payoutRatio)`                           | external onlyAdmin whenNotPaused | Admin/oracle batch-settles matured policies.        | Claims Settlement |
| `withdrawLP(uint256 lpTokenAmount)`                                                 | external whenNotPaused           | LP burns tokens to withdraw available share.        | LP Exit           |

> **Pertinent Workflow Functions**: `depositLP`, `createPolicy`, `settlePolicies`, `withdrawLP`.

---

## User Workflows

### 1. Liquidity Provider (LP)

1. **Deposit**: Approve `stablecoin.transferFrom` and call `depositLP(amount)`.
2. **Receive LP Tokens**: `lpBalances[msg.sender]` increases; represents share of pool.
3. **Monitor**: Track `capitalPool` and yield (in future phases).
4. **Withdraw**: Call `withdrawLP(tokenAmount)` after liquidity buffer check; tokens burn and stablecoin returns.

### 2. Policyholder

1. **Purchase Policy**: Approve stablecoin; call `createPolicy(premium, maxPayout, duration, region)`.
2. **Await Maturity**: Off-chain oracle monitors region metrics.
3. **Payout**: When `endTime` is reached, oracle/admin calls `settlePolicies`.
4. **Receive Payout**: `stablecoin.transfer(user, payout)` executed in batch.

### 3. Oracle / Admin

1. **Pause/Unpause** (if needed): Call `pause()` / `unpause()`.
2. **Set Reserve Ratio**: Adjust buffer via `setReserveRatio(newRatioBps)`.
3. **Batch Settlement**:

   * Off-chain: Fetch data, compute `payoutRatio` and `policyIds` list.
   * On-chain: Call `settlePolicies(policyIds, payoutRatio)`.
4. **Governance** (future): Transition to DAO and upgradeable modules.

---

## Deployment & Testing

1. **Compile**: `npx hardhat compile`
2. **Deploy**: Use sample script or via Hardhat console:

   ```bash
   const BlockBima = await ethers.getContractFactory("BlockBimaMVP");
   const instance = await BlockBima.deploy(STABLE_ADDRESS, ADMIN_ADDRESS);
   ```
3. **Run Tests**: `npx hardhat test test/BlockBimaMVP.test.js`

---



---

*For questions or contributions, contact [kennedy@blockbima.com](mailto:kennedy@blockbima.com).*
