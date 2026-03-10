// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev Minimal Uniswap v3 SwapRouter interface (Base mainnet: 0x2626664c2603336E57B271c5C0b26F421741e481)
interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24  fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata params)
        external payable returns (uint256 amountOut);
}

/**
 * @title PartnerVault
 * @notice Accounting boundary for provable PSRE buys.
 *         Each registered partner gets exactly one PartnerVault, deployed via
 *         PartnerVaultFactory (EIP-1167 clone). The vault address is the
 *         partner's permanent on-chain identity for reward accounting.
 *
 * @dev Dev Spec v2.3, Section 2.3
 *      - Only buy() updates cumBuy (monotonically increasing)
 *      - No sell() in v1
 *      - distribute() moves PSRE out without affecting accounting
 *      - updateOwner() allows wallet migration without losing EMA history
 */
contract PartnerVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @notice Cumulative PSRE received through vault buys since genesis.
    uint256 public cumBuy;

    /// @notice Wallet that controls this vault.
    address public owner;

    /// @notice Pending owner for two-step ownership transfer.
    address public pendingOwner;

    address public psre;
    address public router;
    address public inputToken;
    address public rewardEngine;

    bool private _initialized;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event Bought(address indexed vault, uint256 amountIn, uint256 psreOut, uint256 cumBuy);
    event Distributed(address indexed vault, address indexed to, uint256 amount);
    event OwnershipTransferStarted(address indexed currentOwner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyOwner() {
        require(msg.sender == owner, "PartnerVault: not owner");
        _;
    }

    // -------------------------------------------------------------------------
    // Initializer
    // -------------------------------------------------------------------------

    function initialize(
        address _owner,
        address _psre,
        address _router,
        address _inputToken,
        address _rewardEngine
    ) external {
        require(!_initialized,          "PartnerVault: already initialized");
        require(_owner       != address(0), "PartnerVault: zero owner");
        require(_psre        != address(0), "PartnerVault: zero psre");
        require(_router      != address(0), "PartnerVault: zero router");
        require(_inputToken  != address(0), "PartnerVault: zero inputToken");
        require(_rewardEngine != address(0),"PartnerVault: zero rewardEngine");

        _initialized  = true;
        owner         = _owner;
        psre          = _psre;
        router        = _router;
        inputToken    = _inputToken;
        rewardEngine  = _rewardEngine;
    }

    // -------------------------------------------------------------------------
    // buy()
    // -------------------------------------------------------------------------

    /**
     * @notice Swap inputToken -> PSRE and record the buy.
     *         ONLY function that updates cumBuy.
     *
     * @param amountIn      Amount of inputToken to spend.
     * @param minAmountOut  Minimum PSRE to receive. MUST be non-zero (slippage protection).
     * @param deadline      Unix timestamp after which swap reverts.
     * @param fee           Uniswap v3 pool fee tier (e.g. 3000 = 0.3%).
     */
    function buy(
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline,
        uint24  fee
    ) external onlyOwner nonReentrant returns (uint256 psreOut) {
        require(amountIn     > 0,                  "PartnerVault: zero amountIn");
        require(minAmountOut > 0,                  "PartnerVault: slippage protection required");
        require(deadline >= block.timestamp,        "PartnerVault: expired deadline");

        IERC20(inputToken).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(inputToken).forceApprove(router, amountIn);

        uint256 psreBefore = IERC20(psre).balanceOf(address(this));

        ISwapRouter(router).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn:           inputToken,
                tokenOut:          psre,
                fee:               fee,
                recipient:         address(this),
                deadline:          deadline,
                amountIn:          amountIn,
                amountOutMinimum:  minAmountOut,
                sqrtPriceLimitX96: 0
            })
        );

        uint256 psreAfter = IERC20(psre).balanceOf(address(this));
        psreOut = psreAfter - psreBefore;
        require(psreOut > 0, "PartnerVault: zero psreOut");

        cumBuy += psreOut;
        emit Bought(address(this), amountIn, psreOut, cumBuy);
    }

    // -------------------------------------------------------------------------
    // distribute()
    // -------------------------------------------------------------------------

    function distribute(address to, uint256 amount) external onlyOwner nonReentrant {
        require(to     != address(0), "PartnerVault: zero recipient");
        require(amount > 0,           "PartnerVault: zero amount");
        IERC20(psre).safeTransfer(to, amount);
        emit Distributed(address(this), to, amount);
    }

    // -------------------------------------------------------------------------
    // Ownership (two-step)
    // -------------------------------------------------------------------------

    function updateOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "PartnerVault: zero newOwner");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "PartnerVault: not pending owner");
        address previous = owner;
        owner        = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(previous, owner);
    }

    // -------------------------------------------------------------------------
    // View
    // -------------------------------------------------------------------------

    function psreBalance() external view returns (uint256) {
        return IERC20(psre).balanceOf(address(this));
    }
}
