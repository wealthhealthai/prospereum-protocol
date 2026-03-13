// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev Minimal PSRE mint interface used by MockRouter.
interface IPSRE2 {
    function mint(address to, uint256 amount) external;
}

/// @dev Mock Uniswap v3 SwapRouter for invariant tests.
///      Instead of pulling real PSRE from a pool, it mints PSRE directly to the recipient.
///      Requires MockRouter to hold MINTER_ROLE on PSRE.
///
///      Exchange rate: 1 USDC (6 dec) = 0.1 PSRE (18 dec).
///      Derivation: 1e6 USDC units * 1e11 = 1e17 PSRE units = 0.1 PSRE.
contract MockRouter {
    IPSRE2 public immutable psre;

    /// @notice 0.1 PSRE per 1 USDC unit (in raw token units: 1e6 USDC → 1e17 PSRE).
    uint256 public constant PSRE_PER_USDC = 1e11;

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

    constructor(address _psre) {
        psre = IPSRE2(_psre);
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        returns (uint256 amountOut)
    {
        amountOut = params.amountIn * PSRE_PER_USDC;
        if (amountOut == 0) amountOut = 1;
        psre.mint(params.recipient, amountOut);
        return amountOut;
    }
}
