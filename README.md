# OpenIntent Protocol (Demo)

Brief demo for the idea **Intent + Solver Auction + Settlement**.

## Idea
- **Maker** signs an off-chain `Intent` (EIP-712): wants to exchange `tokenIn` -> `tokenOut`.
- **Relayer/anyone** posts intent to chain.
- **Solvers** sends bid `amountOut` (whoever pays more tokenOut wins).
- After `deadline`, anyone can `finalize()` to settle:
  - Maker receives `tokenOut`
  - The winning solver receives `tokenIn` which is escrow

> This is an educational demo. There are no withdraw bid losers, real slashing, partial fill, multi-route, etc.

## Repo structure
- `contracts/OpenIntentBook.sol`: core contract
- `contracts/MockERC20.sol`: token mock
- `test/openintent.test.js`: end-to-end testing
- `scripts/deploy.js`: deploy local

## Request
- Node.js 18+ (recommended 20+)

## Install
```bash
npm install
```

## Test
```bash
npm test
```

## Run local node + deploy
Terminal 1:
```bash
npm run node
```

Terminal 2:
```bash
npm run deploy
```

## Development direction (suggested)
- Standardized Intent (EIP draft), add `recipient`, `fee`, `partialFill`.
- Solver bonding/slashing + dispute window.
- Off-chain solver bot + UI intent creation.
- Batch settlement, gas optimization.
