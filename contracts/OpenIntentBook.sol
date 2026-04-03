// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * OpenIntentBook (demo)
 * - User signs an Intent off-chain (EIP-712).
 * - Anyone can post the intent on-chain (typically a relayer).
 * - Solvers submit bids and bond.
 * - After deadline, anyone can finalize: best bid wins.
 * - Settlement: maker's tokenIn escrow -> solver; solver pays tokenOut -> maker.
 *
 * This is a minimal demo, not production-safe.
 */
contract OpenIntentBook is EIP712 {
    using ECDSA for bytes32;

    // ====== Types ======

    struct Intent {
        address maker;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        uint64 deadline; // unix seconds
        uint256 nonce;
    }

    struct Bid {
        address solver;
        uint256 amountOut; // amount solver will pay maker in tokenOut
        uint256 bond;      // simple ETH bond (demo)
        bool active;
    }

    bytes32 public constant INTENT_TYPEHASH = keccak256(
        "Intent(address maker,address tokenIn,address tokenOut,uint256 amountIn,uint256 minAmountOut,uint64 deadline,uint256 nonce)"
    );

    enum Status {
        None,
        Posted,
        Finalized,
        Cancelled
    }

    struct IntentState {
        Status status;
        uint256 bestBidId;
        uint256 bidCount;
        bool escrowed;
    }

    // ====== Storage ======

    mapping(bytes32 => IntentState) public intentState; // intentHash => state
    mapping(bytes32 => mapping(uint256 => Bid)) public bids; // intentHash => bidId => Bid

    mapping(address => mapping(uint256 => bool)) public nonceUsed; // maker => nonce => used

    // ====== Events ======

    event IntentPosted(bytes32 indexed intentHash, address indexed maker, address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, uint64 deadline, uint256 nonce);
    event BidSubmitted(bytes32 indexed intentHash, uint256 indexed bidId, address indexed solver, uint256 amountOut, uint256 bond);
    event BestBidUpdated(bytes32 indexed intentHash, uint256 indexed bidId, uint256 amountOut);
    event IntentFinalized(bytes32 indexed intentHash, uint256 indexed winningBidId, address indexed solver, uint256 amountOut);
    event IntentCancelled(bytes32 indexed intentHash);

    // ====== Errors ======

    error InvalidSignature();
    error IntentExpired();
    error IntentNotPosted();
    error IntentAlreadyFinalized();
    error IntentNotFinalizable();
    error NonceAlreadyUsed();
    error NotMaker();
    error ZeroAddress();
    error InvalidBid();

    constructor() EIP712("OpenIntent Protocol", "0.1") {}

    // ====== Hashing / verification ======

    function hashIntent(Intent calldata i) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                INTENT_TYPEHASH,
                i.maker,
                i.tokenIn,
                i.tokenOut,
                i.amountIn,
                i.minAmountOut,
                i.deadline,
                i.nonce
            )
        );
        return _hashTypedDataV4(structHash);
    }

    function verify(Intent calldata i, bytes calldata signature) public view returns (address signer) {
        bytes32 digest = hashIntent(i);
        signer = digest.recover(signature);
    }

    // ====== Core flow ======

    function postIntent(Intent calldata i, bytes calldata signature) external returns (bytes32 intentHash) {
        if (i.maker == address(0) || i.tokenIn == address(0) || i.tokenOut == address(0)) revert ZeroAddress();
        if (block.timestamp > i.deadline) revert IntentExpired();
        if (nonceUsed[i.maker][i.nonce]) revert NonceAlreadyUsed();

        address signer = verify(i, signature);
        if (signer != i.maker) revert InvalidSignature();

        intentHash = hashIntent(i);
        IntentState storage st = intentState[intentHash];
        if (st.status != Status.None) {
            // allow idempotent posting
            return intentHash;
        }

        st.status = Status.Posted;

        emit IntentPosted(intentHash, i.maker, i.tokenIn, i.tokenOut, i.amountIn, i.minAmountOut, i.deadline, i.nonce);
    }

    /**
     * Maker escrows tokenIn into this contract. Requires approval.
     * For demo simplicity: escrow is separate from posting.
     */
    function escrow(Intent calldata i) external {
        if (msg.sender != i.maker) revert NotMaker();
        bytes32 intentHash = hashIntent(i);
        IntentState storage st = intentState[intentHash];
        if (st.status != Status.Posted) revert IntentNotPosted();
        if (block.timestamp > i.deadline) revert IntentExpired();
        if (st.escrowed) return;

        nonceUsed[i.maker][i.nonce] = true;
        st.escrowed = true;

        IERC20(i.tokenIn).transferFrom(i.maker, address(this), i.amountIn);
    }

    /**
     * Solvers bid with an amountOut and a simple ETH bond.
     */
    function submitBid(Intent calldata i, uint256 amountOut) external payable returns (bytes32 intentHash, uint256 bidId) {
        if (amountOut == 0) revert InvalidBid();
        if (block.timestamp > i.deadline) revert IntentExpired();

        intentHash = hashIntent(i);
        IntentState storage st = intentState[intentHash];
        if (st.status != Status.Posted) revert IntentNotPosted();

        st.bidCount += 1;
        bidId = st.bidCount;

        bids[intentHash][bidId] = Bid({ solver: msg.sender, amountOut: amountOut, bond: msg.value, active: true });

        emit BidSubmitted(intentHash, bidId, msg.sender, amountOut, msg.value);

        // Update best bid (highest amountOut)
        if (st.bestBidId == 0 || amountOut > bids[intentHash][st.bestBidId].amountOut) {
            st.bestBidId = bidId;
            emit BestBidUpdated(intentHash, bidId, amountOut);
        }
    }

    /**
     * Finalize after deadline. Winner must have approved tokenOut to this contract.
     * Settlement:
     * - transfer tokenOut from solver -> maker
     * - transfer escrowed tokenIn from contract -> solver
     * - return bonds: winner gets bond back; losers can withdraw separately (not implemented here)
     */
    function finalize(Intent calldata i) external returns (bytes32 intentHash, uint256 winningBidId) {
        intentHash = hashIntent(i);
        IntentState storage st = intentState[intentHash];
        if (st.status != Status.Posted) revert IntentNotPosted();
        if (block.timestamp <= i.deadline) revert IntentNotFinalizable();
        if (!st.escrowed) revert IntentNotFinalizable();

        winningBidId = st.bestBidId;
        if (winningBidId == 0) revert IntentNotFinalizable();

        Bid storage win = bids[intentHash][winningBidId];
        if (!win.active) revert InvalidBid();
        if (win.amountOut < i.minAmountOut) revert InvalidBid();

        st.status = Status.Finalized;

        // Pull tokenOut from solver to maker
        IERC20(i.tokenOut).transferFrom(win.solver, i.maker, win.amountOut);
        // Pay tokenIn to solver
        IERC20(i.tokenIn).transfer(win.solver, i.amountIn);

        // Return winner bond (demo)
        if (win.bond > 0) {
            (bool ok,) = payable(win.solver).call{value: win.bond}("");
            require(ok, "bond refund failed");
        }

        emit IntentFinalized(intentHash, winningBidId, win.solver, win.amountOut);
    }

    /**
     * Maker can cancel before escrow (demo).
     */
    function cancel(Intent calldata i) external {
        if (msg.sender != i.maker) revert NotMaker();
        bytes32 intentHash = hashIntent(i);
        IntentState storage st = intentState[intentHash];
        if (st.status != Status.Posted) revert IntentNotPosted();
        if (st.escrowed) revert IntentNotFinalizable();

        st.status = Status.Cancelled;
        nonceUsed[i.maker][i.nonce] = true;

        emit IntentCancelled(intentHash);
    }
}
