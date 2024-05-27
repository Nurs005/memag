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

    IUniswapV3Pool private pool;
    IERC20 public tokenContract;
    IERC20 public purchaseTokenContract;

    address private receiverAddress;
    bool public isSaleStart;
    bool public isSaleEnd;
    uint256 public tokenPriceUSDT;
    uint256 public minPurchaseAmount = 1;
    uint8 public stage = 1;
    uint256 public minWei = 100000000000;

    mapping(address => uint256) private _tokensBought;
    mapping(address => uint256) private _lastClaimTime;

    event BuyTokens(address indexed addr, uint256 amount);
    event SaleStatusChanged(bool newStatus);
    event PriceUpdated(uint256 newPrice);
    event MinPurchaseAmountChanged(uint256 newMinPurchaseAmount);
    event SaleStarded(bool isSaleStarted);

    uint256[15] public priceStruct;
    uint256[15] public stagePeriods;
    uint constantValue = 714285710000;

    constructor(
        address initialOwner,
        address DoggyAi,
        address stableToken,
        address pools
    ) Ownable(initialOwner) {
        tokenContract = IERC20(DoggyAi);
        purchaseTokenContract = IERC20(stableToken);
        receiverAddress = initialOwner;
        tokenPriceUSDT = 289;
        pool = IUniswapV3Pool(pools);
    }

    function initializeStages() internal {
        uint8 length = 15;
        for (uint8 i = 0; i < length; i++) {
            if (i == 0) {
                priceStruct[i] = tokenPriceUSDT;
                stagePeriods[i] = block.timestamp;
            } else if (i == 14) {
                unchecked {
                    priceStruct[i] = (priceStruct[i - 1] * 110) / 100;
                }
                stagePeriods[i] = stagePeriods[i - 1] + 4 days;
            } else {
                unchecked {
                    priceStruct[i] = (priceStruct[i - 1] * 110) / 100;
                }
                stagePeriods[i] = stagePeriods[i - 1] + 5 days;
            }
        }
    }

    function startSale(bool _isSaleStart) external onlyOwner {
        isSaleStart = _isSaleStart;
        initializeStages();
        emit SaleStarded(_isSaleStart);
    }

    function whichStage(uint8 _stage) public {
        for (uint8 i = _stage; i < priceStruct.length; i++) {
            if (i == 14) {
                if (
                    purchaseTokenContract.balanceOf(address(this)) >=
                    constantValue * i ||
                    block.timestamp >= stagePeriods[i]
                ) {
                    stage = i + 1;
                    tokenPriceUSDT = priceStruct[i];
                } else {
                    break;
                }
            } else {
                if (
                    purchaseTokenContract.balanceOf(address(this)) >=
                    constantValue * i ||
                    block.timestamp >= stagePeriods[i]
                ) {
                    stage = i + 1;
                    tokenPriceUSDT = priceStruct[i];
                } else {
                    break;
                }
            }
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

    function calculatePriceWEI(uint weiAmount) public view returns (uint256) {
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
        uint256 weiPerUSDT = FullMath.mulDiv(amount1, 1e6, amount0);
        uint256 weiPerYourToken = FullMath.mulDiv(
            tokenPriceUSDT,
            weiPerUSDT,
            10 ** 6
        );
        uint256 amountToken = (weiAmount / weiPerYourToken) * 10 ** 18;
        return amountToken;
    }

    function calculateAct() public view returns (uint) {
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
        uint256 weiPerUSDT = FullMath.mulDiv(amount1, 1e6, amount0);
        uint256 weiPerYourToken = FullMath.mulDiv(
            tokenPriceUSDT,
            weiPerUSDT,
            10 ** 6
        );
        return weiPerYourToken;
    }

    function buyTokenByETH() public payable nonReentrant {
        require(isSaleStart, "Sale doesn't start");
        if (isSaleEnd) {
            revert("Sale End");
        }
        require(msg.value >= minWei, "Insufficient purchase eth to buy tokens");
        uint amountWei = msg.value;
        whichStage(stage);
        uint amount = calculatePriceWEI(amountWei);
        if (amount == 0) {
            revert("Wrong amount wei");
        }
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

    function buyTokensBuyUSDT(uint256 usdtAmount) public nonReentrant {
        require(isSaleStart, "Sale doesn't start");
        if (isSaleEnd) {
            revert("Sale End");
        }
        require(
            usdtAmount >= minPurchaseAmount,
            "Token amount is below the minimum purchase amount"
        );
        whichStage(stage);
        uint tokensAmount = (usdtAmount * (10 ** 18)) / tokenPriceUSDT;
        require(tokensAmount > 0, "Insufficient purchase token to buy tokens");
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

    function toggleisSaleEnd(bool _isSaleEnd) public onlyOwner {
        isSaleEnd = _isSaleEnd;
    }

    function totalTokensBought(address account) public view returns (uint256) {
        return _tokensBought[account];
    }

    receive() external payable {}
}
