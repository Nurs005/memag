// SPDX-License-Identifier: MIT

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

pragma solidity 0.8.20;

contract DoggyAiPresale is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public tokenContract;
    IERC20 public purchaseTokenContract;

    address private receiverAddress;
    bool public isSaleEndTime = false;
    uint256 public tokenPriceUSDT;
    uint256 public tokenPriceETH;
    uint256 public minPurchaseAmount = 1;
    uint48 startTime;
    uint8 public stage = 1;
    uint256 public minWei = 1000000000;
    IUniswapV3Pool private pool;

    mapping(address => uint256) private _tokensBought;
    mapping(address => uint256) private _lastClaimTime;

    event BuyTokens(address indexed addr, uint256 amount);
    event SaleStatusChanged(bool newStatus);
    event PriceUpdated(uint256 newPrice);
    event MinPurchaseAmountChanged(uint256 newMinPurchaseAmount);

    uint256[15] public priceStruct;
    uint256[15] public blanceStruct;

    constructor(
        address initialOwner,
        address DoggyAi,
        address stableToken,
        address pools
    ) Ownable(initialOwner) {
        tokenContract = IERC20(DoggyAi);
        purchaseTokenContract = IERC20(stableToken);
        receiverAddress = initialOwner;
        tokenPriceUSDT = 288800;
        startTime = uint48(block.timestamp);
        pool = IUniswapV3Pool(pools);
        initializeStages();
        calculatePriceWEI(1);
    }

    function initializeStages() internal {
        uint length = 15;
        for (uint8 i = 0; i < length; i++) {
            require(
                i < priceStruct.length && i < blanceStruct.length,
                "Index out of bounds"
            );

            if (i == 0) {
                priceStruct[i] = tokenPriceUSDT;
                blanceStruct[i] = 0;
            } else {
                unchecked {
                    priceStruct[i] = (priceStruct[i - 1] * 110) / 100 + 1;
                }
                blanceStruct[i] = blanceStruct[i - 1] + 714285710000000000000;
            }
        }
    }

    function whichStage(uint8 _stage) public {
        for (uint8 i = _stage - 1; i < priceStruct.length; i++)
            if (
                purchaseTokenContract.balanceOf(address(this)) >=
                blanceStruct[i]
            ) {
                stage = i + 1;
                tokenPriceUSDT = priceStruct[i];
            }
    }

    function ownerWithdrawPurchaseTokens() external nonReentrant onlyOwner {
        uint256 balance = purchaseTokenContract.balanceOf(address(this));
        require(balance > 0, "No tokens to withdraw");
        purchaseTokenContract.safeTransfer(receiverAddress, balance);
    }

    function ownerWithdrawTokens() external nonReentrant onlyOwner {
        uint256 freeTokens = tokenContract.balanceOf(address(this));
        require(freeTokens > 0, "No free tokens to withdraw");
        tokenContract.safeTransfer(receiverAddress, freeTokens);
    }

    function setMinPurchaseAmount(
        uint256 _newMinPurchaseAmount
    ) external onlyOwner {
        require(_newMinPurchaseAmount > 0, "Amount cannot be zero");
        minPurchaseAmount = _newMinPurchaseAmount;
        emit MinPurchaseAmountChanged(_newMinPurchaseAmount);
    }

    function calculatePriceWEI(uint weiAmount) public returns (uint256) {
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();

        uint256 amount0 = FullMath.mulDiv(
            pool.liquidity(),
            FixedPoint96.Q96,
            sqrtPriceX96
        );
        uint256 amount1 = FullMath.mulDiv(
            pool.liquidity(),
            sqrtPriceX96,
            FixedPoint96.Q96
        );
        uint256 weiPerUSDT = FullMath.mulDiv(amount0, 1e18, amount1);
        uint256 weiPerYourToken = FullMath.mulDiv(
            tokenPriceUSDT,
            weiPerUSDT,
            1e6
        );
        uint256 amountToken = (weiAmount / weiPerYourToken) * 10 ** 18;
        if (weiPerYourToken != tokenPriceETH) {
            tokenPriceETH = weiPerYourToken;
        }
        return amountToken;
    }

    function buyTokensBuyUSDT(uint256 usdtAmount) public nonReentrant {
        require(!isSaleEndTime, "Sale has ended");
        require(
            usdtAmount >= minPurchaseAmount,
            "Token amount is below the minimum purchase amount"
        );
        whichStage(stage);
        uint tokensAmount = (usdtAmount * (10 ** 18)) / tokenPriceUSDT;
        require(tokensAmount >= 0, "Insufficient purchase token to buy tokens");
        require(
            tokensAmount <= tokenContract.balanceOf(address(this)),
            "Insufficient tokens in contract"
        );
        purchaseTokenContract.safeTransferFrom(
            msg.sender,
            address(this),
            usdtAmount
        );
        require(
            tokenContract.transfer(msg.sender, tokensAmount),
            "Tranfer failed"
        );

        _tokensBought[msg.sender] += tokensAmount;
        emit BuyTokens(msg.sender, tokensAmount);
    }

    function buyTokenByETH() public payable nonReentrant {
        require(!isSaleEndTime, "Sale has ended");
        require(tokenPriceETH > 0, "Price not set");
        require(msg.value >= minWei, "Insufficient purchase eth to buy tokens");
        uint amountWei = msg.value;
        whichStage(stage);
        uint amount = calculatePriceWEI(amountWei);
        require(
            amount <= tokenContract.balanceOf(address(this)),
            "Insufficient tokens in contract"
        );
        (bool succes, ) = address(this).call{value: msg.value}("");
        if (!succes) {
            revert("Transfer eth error");
        }

        require(tokenContract.transfer(msg.sender, amount), "Tranfer failed");

        _tokensBought[msg.sender] += amount;
        emit BuyTokens(msg.sender, amount);
    }

    function tuppleIsSaleEnd(bool isSale) public onlyOwner {
        isSaleEndTime = isSale;
    }

    function totalTokensBought(address account) public view returns (uint256) {
        return _tokensBought[account];
    }

    receive() external payable {}
}
