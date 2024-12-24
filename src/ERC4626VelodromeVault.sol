// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IVelodromeRouter {
    struct Route {
        address from;
        address to;
        bool stable;
        address factory;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut(uint256 amountIn, Route[] memory routes) 
        external view returns (uint256[] memory amounts);
}

contract ERC4626VelodromeVault is ERC4626, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable usdc;
    address public immutable targetToken;
    address public immutable velodromeRouter;
    address public immutable velodromeFactory;

    uint256 private constant SLIPPAGE_TOLERANCE = 100; // 0.5%
    uint256 private constant SLIPPAGE_DENOMINATOR = 10000;

    event Deposit(address indexed user, uint256 assets, uint256 shares);
    event Withdraw(address indexed user, uint256 assets, uint256 shares);
    event Swap(address indexed user, uint256 amountIn, uint256 amountOut);

    constructor(
        IERC20 _usdc,
        IERC20 _targetToken,
        address _velodromeRouter,
        address _velodromeFactory,
        string memory name,
        string memory symbol
    ) ERC4626(_usdc) ERC20(name, symbol) {
        require(address(_usdc) != address(0), "Invalid USDC address");
        require(address(_targetToken) != address(0), "Invalid target token address");
        require(_velodromeRouter != address(0), "Invalid Velodrome router address");
        require(_velodromeFactory != address(0), "Invalid Velodrome factory address");

        usdc = address(_usdc);
        targetToken = address(_targetToken);
        velodromeRouter = _velodromeRouter;
        velodromeFactory = _velodromeFactory;
    }

    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256 shares) {
        shares = super.deposit(assets, receiver);
        _swapUSDCForTargetToken(assets);
        emit Deposit(receiver, assets, shares);
    }

    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256 assets) {
        assets = super.mint(shares, receiver);
        _swapUSDCForTargetToken(assets);
        emit Deposit(receiver, assets, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner) public override nonReentrant returns (uint256 shares) {
        uint256 targetTokenAmount = _swapTargetTokenToUSDC(assets);
        shares = super.withdraw(targetTokenAmount, receiver, owner);
        emit Withdraw(owner, assets, shares);
    }

    function redeem(uint256 shares, address receiver, address owner) public override nonReentrant returns (uint256 assets) {
        assets = super.redeem(shares, receiver, owner);
        uint256 targetTokenAmount = _swapTargetTokenToUSDC(assets);
        IERC20(usdc).safeTransfer(receiver, targetTokenAmount);
        emit Withdraw(owner, assets, shares);
    }

    function _swapUSDCForTargetToken(uint256 amountIn) internal returns (uint256 amountOut) {
        require(amountIn > 0, "Invalid swap amount");

        IERC20(usdc).forceApprove(velodromeRouter, amountIn);

        IVelodromeRouter.Route[] memory routes = new IVelodromeRouter.Route[](1);
        routes[0] = IVelodromeRouter.Route({
            from: usdc,
            to: targetToken,
            stable: false,
            factory: velodromeFactory
        });

        uint256 amountOutMin = _calculateMinAmountOut(amountIn);

        uint256[] memory amounts = IVelodromeRouter(velodromeRouter).swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            routes,
            address(this),
            block.timestamp + 1 hours
        );

        amountOut = amounts[amounts.length - 1];
        emit Swap(msg.sender, amountIn, amountOut);
        return amountOut;
    }

    function _swapTargetTokenToUSDC(uint256 amountIn) internal returns (uint256 amountOut) {
        require(amountIn > 0, "Invalid swap amount");

        IERC20(targetToken).forceApprove(velodromeRouter, amountIn);

        IVelodromeRouter.Route[] memory routes = new IVelodromeRouter.Route[](1);
        routes[0] = IVelodromeRouter.Route({
            from: targetToken,
            to: usdc,
            stable: false,
            factory: velodromeFactory
        });

        uint256 amountOutMin = _calculateMinAmountOut(amountIn);

        uint256[] memory amounts = IVelodromeRouter(velodromeRouter).swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            routes,
            address(this),
            block.timestamp + 1 hours
        );

        amountOut = amounts[amounts.length - 1];
        emit Swap(msg.sender, amountIn, amountOut);
        return amountOut;
    }

    function _calculateMinAmountOut(uint256 amountIn) internal view returns (uint256) {
        IVelodromeRouter.Route[] memory routes = new IVelodromeRouter.Route[](1);
        routes[0] = IVelodromeRouter.Route({
            from: usdc,
            to: targetToken,
            stable: false,
            factory: velodromeFactory
        });

        uint256[] memory amounts = IVelodromeRouter(velodromeRouter).getAmountsOut(amountIn, routes);
        uint256 expectedAmountOut = amounts[amounts.length - 1];
        return (expectedAmountOut * (SLIPPAGE_DENOMINATOR - SLIPPAGE_TOLERANCE)) / SLIPPAGE_DENOMINATOR;
    }

    function totalAssets() public view override returns (uint256) {
        return IERC20(targetToken).balanceOf(address(this));
    }
}
