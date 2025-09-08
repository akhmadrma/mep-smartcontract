# ProjectEscrow Smart Contract

ProjectEscrow is a robust and secure smart contract system designed to facilitate milestone-based payments between clients and workers. Built on Solidity and leveraging OpenZeppelin libraries, it ensures trustless, transparent, and automated project management for freelance and service-based engagements.

## Features

- **Milestone-Based Escrow:** Funds are deposited and released per milestone, ensuring fair compensation and accountability.
- **Role Management:** Distinct roles for client and worker, with access control for sensitive actions.
- **Project Lifecycle:** Supports project creation, milestone management, approval/rejection flows, deadline extensions, and project cancellation.
- **Refunds:** Automated refund mechanism for abandoned or canceled projects.
- **ERC20 Support:** Handles payments in any ERC20 token.
- **Security:** Utilizes OpenZeppelin's `ReentrancyGuard` and `SafeERC20` for secure fund transfers.

## Contract Structures

- **Project:** Contains client, worker, token, status, milestones, and timestamps.
- **Milestone:** Tracks payout, deadlines, approval status, and responses.
- **ProjectBalance:** Manages deposited, withdrawn, and total funds.
- **CanceledProject & ExtendDeadline:** Handle cancellation and deadline extension requests.

## Key Functions

- `createProject`: Initialize a new project with milestones.
- `depositFunds`: Client deposits funds for the project.
- `requestPayout`: Worker requests payout for a completed milestone.
- `approvePayout`: Client approves payout, releasing funds.
- `requestCancelProject` / `responseCancelProject`: Initiate and respond to project cancellation.
- `requestExtendDeadline` / `responseExtendDeadline`: Manage milestone deadline extensions.
- `issueRefund`: Client can claim a refund if the project is abandoned.
- `completeProject`: Worker marks the project as completed after all milestones are approved and paid.

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
