# OpenIntent Protocol (Demo)

Demo ngắn gọn cho ý tưởng **Intent + Solver Auction + Settlement**.

## Ý tưởng
- **Maker** ký 1 `Intent` off-chain (EIP-712): muốn đổi `tokenIn` -> `tokenOut`.
- **Relayer/anyone** đăng intent lên chain.
- **Solvers** gửi bid `amountOut` (ai trả nhiều tokenOut hơn thì thắng).
- Sau `deadline`, ai cũng có thể `finalize()` để settle:
  - Maker nhận `tokenOut`
  - Solver thắng nhận `tokenIn` đang escrow

> Đây là demo giáo dục. Chưa có withdraw bid losers, slashing thực, partial fill, multi-route, etc.

## Cấu trúc repo
- `contracts/OpenIntentBook.sol`: core contract
- `contracts/MockERC20.sol`: token mock
- `test/openintent.test.js`: test end-to-end
- `scripts/deploy.js`: deploy local

## Yêu cầu
- Node.js 18+ (khuyến nghị 20+)

## Cài đặt
```bash
npm install
```

## Test
```bash
npm test
```

## Chạy local node + deploy
Terminal 1:
```bash
npm run node
```

Terminal 2:
```bash
npm run deploy
```

## Hướng phát triển (gợi ý)
- Intent chuẩn hóa (EIP draft), thêm `recipient`, `fee`, `partialFill`.
- Solver bonding/slashing + dispute window.
- Off-chain solver bot + UI tạo intent.
- Batch settlement, gas optimization.
