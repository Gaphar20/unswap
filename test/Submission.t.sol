// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Submission.sol";

contract SubmissionTest is Test {
    Submission public submission;

    address public constant ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDT_WETH_PAIR = 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852;

    address public WHALE;
    address public user;
    address public recipient;

    function setUp() public {
        WHALE = vm.parseAddress("0xf977814e90da44bfa03b6295a0616a897441acec");
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 25_949_200);

        submission = new Submission();

        user = makeAddr("user");
        recipient = makeAddr("recipient");

        // Fund user with USDT and WETH from whale
        uint256 whaleUsdt = IERC20(USDT).balanceOf(WHALE);
        uint256 whaleWeth = IERC20(WETH).balanceOf(WHALE);
        console.log("WHALE USDT balance:", whaleUsdt);
        console.log("WHALE WETH balance:", whaleWeth);

        vm.startPrank(WHALE);
        (bool s1, ) = USDT.call(abi.encodeWithSignature("transfer(address,uint256)", user, 10_000 * 1e6));
        require(s1, "USDT transfer from WHALE failed");
        (bool s2, ) = WETH.call(abi.encodeWithSignature("transfer(address,uint256)", user, 12 * 1e18));
        require(s2, "WETH transfer from WHALE failed");
        vm.stopPrank();
    }

    function _approveToken(address token, address owner, address spender, uint256 amount) internal {
        vm.startPrank(owner);
        (bool s1, ) = token.call(abi.encodeWithSignature("approve(address,uint256)", spender, 0));
        require(s1, "approve zero failed");
        (bool s2, ) = token.call(abi.encodeWithSignature("approve(address,uint256)", spender, amount));
        require(s2, "approve failed");
        vm.stopPrank();
    }

    function testSwapUsdtForWethSuccess() public {
        uint256 amountIn = 100 * 1e6; // 100 USDT
        uint256 amountOutMin = 1;     // modest min out
        uint256 deadline = block.timestamp + 300;

        _approveToken(USDT, user, address(submission), amountIn);

        uint256 wethBefore = IERC20(WETH).balanceOf(recipient);
        uint256 usdtUserBefore = IERC20(USDT).balanceOf(user);

        vm.prank(user);
        uint256 amountOut = submission.swapUsdtForWeth(amountIn, amountOutMin, recipient, deadline);

        uint256 wethAfter = IERC20(WETH).balanceOf(recipient);
        uint256 usdtUserAfter = IERC20(USDT).balanceOf(user);

        assertTrue(amountOut > 0, "amountOut should be > 0");
        assertEq(wethAfter - wethBefore, amountOut, "recipient WETH balance increase should match amountOut");
        assertEq(usdtUserBefore - usdtUserAfter, amountIn, "user USDT balance should decrease by amountIn");

        // Assert no leftover Router approval on Submission contract
        assertEq(IERC20(USDT).allowance(address(submission), ROUTER), 0, "Router allowance should be 0");
    }

    function testAddUsdtWethLiquiditySuccess() public {
        uint256 usdtDesired = 1000 * 1e6; // 1000 USDT
        uint256 wethDesired = 1 * 1e18;   // 1 WETH
        uint256 usdtMin = 1;
        uint256 wethMin = 1;
        uint256 deadline = block.timestamp + 300;

        _approveToken(USDT, user, address(submission), usdtDesired);
        _approveToken(WETH, user, address(submission), wethDesired);

        uint256 lpBefore = IERC20(USDT_WETH_PAIR).balanceOf(recipient);

        vm.prank(user);
        (uint256 usdtUsed, uint256 wethUsed, uint256 liquidity) = submission.addUsdtWethLiquidity(
            usdtDesired,
            wethDesired,
            usdtMin,
            wethMin,
            recipient,
            deadline
        );

        uint256 lpAfter = IERC20(USDT_WETH_PAIR).balanceOf(recipient);

        assertTrue(usdtUsed > 0 && usdtUsed <= usdtDesired, "usdtUsed valid");
        assertTrue(wethUsed > 0 && wethUsed <= wethDesired, "wethUsed valid");
        assertTrue(liquidity > 0, "liquidity > 0");
        assertEq(lpAfter - lpBefore, liquidity, "recipient LP token balance increase should match liquidity");

        // Assert no leftover Router approval on Submission contract
        assertEq(IERC20(USDT).allowance(address(submission), ROUTER), 0, "Router USDT allowance should be 0");
        assertEq(IERC20(WETH).allowance(address(submission), ROUTER), 0, "Router WETH allowance should be 0");
    }

    function testAddLiquidityRefundsUnusedTokens() public {
        // Intentionally provide an excess of WETH relative to USDT ratio
        uint256 usdtDesired = 100 * 1e6; // 100 USDT
        uint256 wethDesired = 10 * 1e18; // 10 WETH (disproportionately high)
        uint256 usdtMin = 1;
        uint256 wethMin = 1;
        uint256 deadline = block.timestamp + 300;

        _approveToken(USDT, user, address(submission), usdtDesired);
        _approveToken(WETH, user, address(submission), wethDesired);

        uint256 userUsdtBefore = IERC20(USDT).balanceOf(user);
        uint256 userWethBefore = IERC20(WETH).balanceOf(user);

        vm.prank(user);
        (uint256 usdtUsed, uint256 wethUsed, ) = submission.addUsdtWethLiquidity(
            usdtDesired,
            wethDesired,
            usdtMin,
            wethMin,
            user,
            deadline
        );

        uint256 userUsdtAfter = IERC20(USDT).balanceOf(user);
        uint256 userWethAfter = IERC20(WETH).balanceOf(user);

        // Verify net tokens spent by user equals actual usdtUsed and wethUsed
        assertEq(userUsdtBefore - userUsdtAfter, usdtUsed, "User net USDT spent should equal usdtUsed");
        assertEq(userWethBefore - userWethAfter, wethUsed, "User net WETH spent should equal wethUsed");

        // Since wethDesired (10 WETH) is much higher than needed for 100 USDT, wethUsed < wethDesired
        assertTrue(wethUsed < wethDesired, "Unused WETH should exist and be refunded");

        // Assert submission contract holds no leftover tokens
        assertEq(IERC20(USDT).balanceOf(address(submission)), 0, "Submission should hold 0 USDT");
        assertEq(IERC20(WETH).balanceOf(address(submission)), 0, "Submission should hold 0 WETH");
    }

    function testSwapUsdtForWethZeroAmountInReverts() public {
        vm.prank(user);
        vm.expectRevert("Invalid amountIn");
        submission.swapUsdtForWeth(0, 1, recipient, block.timestamp + 300);
    }

    function testSwapUsdtForWethZeroRecipientReverts() public {
        vm.prank(user);
        vm.expectRevert("Invalid recipient");
        submission.swapUsdtForWeth(100 * 1e6, 1, address(0), block.timestamp + 300);
    }

    function testAddLiquidityZeroUsdtDesiredReverts() public {
        vm.prank(user);
        vm.expectRevert("Invalid USDT amount");
        submission.addUsdtWethLiquidity(0, 1e18, 1, 1, recipient, block.timestamp + 300);
    }

    function testAddLiquidityZeroWethDesiredReverts() public {
        vm.prank(user);
        vm.expectRevert("Invalid WETH amount");
        submission.addUsdtWethLiquidity(100 * 1e6, 0, 1, 1, recipient, block.timestamp + 300);
    }

    function testAddLiquidityZeroRecipientReverts() public {
        vm.prank(user);
        vm.expectRevert("Invalid recipient");
        submission.addUsdtWethLiquidity(100 * 1e6, 1e18, 1, 1, address(0), block.timestamp + 300);
    }

    function testSwapSlippageExceededReverts() public {
        uint256 amountIn = 100 * 1e6;
        uint256 amountOutMin = 1000 * 1e18; // impossibly high min WETH out
        uint256 deadline = block.timestamp + 300;

        _approveToken(USDT, user, address(submission), amountIn);
        vm.prank(user);
        vm.expectRevert();
        submission.swapUsdtForWeth(amountIn, amountOutMin, recipient, deadline);
    }

    function testSwapInsufficientAllowanceReverts() public {
        uint256 amountIn = 100 * 1e6;
        uint256 deadline = block.timestamp + 300;

        vm.prank(user);
        // Do not approve submission
        vm.expectRevert();
        submission.swapUsdtForWeth(amountIn, 1, recipient, deadline);
    }
}
