// Repository: https://github.com/Gaphar20/unswap.git
// Commit: b7f6fa4c5ea7852e934873c132686ba47da92ca4
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface IUniswapV2Router02 {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}

contract Submission {
    address private constant ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    function swapUsdtForWeth(
        uint256 amountIn,
        uint256 amountOutMin,
        address recipient,
        uint256 deadline
    ) external nonReentrant returns (uint256 amountOut) {
        require(amountIn > 0, "Invalid amountIn");
        require(recipient != address(0), "Invalid recipient");

        _safeTransferFrom(USDT, msg.sender, address(this), amountIn);

        _safeApprove(USDT, ROUTER, amountIn);

        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = WETH;

        uint256[] memory amounts = IUniswapV2Router02(ROUTER).swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            recipient,
            deadline
        );

        amountOut = amounts[1];

        _safeApprove(USDT, ROUTER, 0);

        return amountOut;
    }

    function addUsdtWethLiquidity(
        uint256 usdtDesired,
        uint256 wethDesired,
        uint256 usdtMin,
        uint256 wethMin,
        address recipient,
        uint256 deadline
    ) external nonReentrant returns (uint256 usdtUsed, uint256 wethUsed, uint256 liquidity) {
        require(usdtDesired > 0, "Invalid USDT amount");
        require(wethDesired > 0, "Invalid WETH amount");
        require(recipient != address(0), "Invalid recipient");

        _safeTransferFrom(USDT, msg.sender, address(this), usdtDesired);
        _safeTransferFrom(WETH, msg.sender, address(this), wethDesired);

        _safeApprove(USDT, ROUTER, usdtDesired);
        _safeApprove(WETH, ROUTER, wethDesired);

        (usdtUsed, wethUsed, liquidity) = IUniswapV2Router02(ROUTER).addLiquidity(
            USDT,
            WETH,
            usdtDesired,
            wethDesired,
            usdtMin,
            wethMin,
            recipient,
            deadline
        );

        _safeApprove(USDT, ROUTER, 0);
        _safeApprove(WETH, ROUTER, 0);

        uint256 usdtUnused = usdtDesired - usdtUsed;
        if (usdtUnused > 0) {
            _safeTransfer(USDT, msg.sender, usdtUnused);
        }

        uint256 wethUnused = wethDesired - wethUsed;
        if (wethUnused > 0) {
            _safeTransfer(WETH, msg.sender, wethUnused);
        }

        return (usdtUsed, wethUsed, liquidity);
    }

    function _safeTransfer(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SafeERC20: transfer failed");
    }

    function _safeTransferFrom(address token, address from, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SafeERC20: transferFrom failed");
    }

    function _safeApprove(address token, address spender, uint256 value) internal {
        if (value > 0) {
            (bool resetSuccess, bytes memory resetData) = token.call(
                abi.encodeWithSelector(IERC20.approve.selector, spender, 0)
            );
            require(resetSuccess && (resetData.length == 0 || abi.decode(resetData, (bool))), "SafeERC20: approve reset failed");
        }

        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.approve.selector, spender, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SafeERC20: approve failed");
    }
}
