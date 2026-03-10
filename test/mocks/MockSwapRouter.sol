// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev Mock Uniswap V3 SwapRouter.
///      On exactInputSingle, consumes inputToken from caller and sends psreOut PSRE to recipient.
///      psreOut is configured at construction for deterministic test output.
contract MockSwapRouter {
    using SafeERC20 for IERC20;

    address public psreToken;
    uint256 public fixedPsreOut;

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

    constructor(address _psreToken, uint256 _fixedPsreOut) {
        psreToken    = _psreToken;
        fixedPsreOut = _fixedPsreOut;
    }

    function setPsreOut(uint256 amount) external {
        fixedPsreOut = amount;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut) {
        // Pull tokenIn from caller (vault already approved)
        IERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);
        // Send fixed PSRE to recipient
        amountOut = fixedPsreOut;
        IERC20(psreToken).safeTransfer(params.recipient, amountOut);
    }
}
