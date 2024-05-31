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
    uint256 public endDate;
    uint256 public minPurchaseAmount = 1;
    uint8 public stage = 1;
    uint256 public minWei = 100000000000;

    mapping(address => uint256) private _tokensBought;
    mapping(address => uint256) private _lastClaimTime;

    event BuyTokens(address indexed addr, uint256 amount);
    event PriceUpdated(uint256 newPrice);
    event MinPurchaseAmountChanged(uint256 newMinPurchaseAmount);
    event SaleStarted(bool isSaleStarted);

    uint256[] public priceStruct;
    uint256[] public stagePeriods;
    //This is the value I use to measure whether we have reached a certain target for price change, this is the volume used for tokenomics stage switching.
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
        uint8 totalDays = 76;
        uint8 period = 5;
        uint8 shorterPeriodLength = 4;
        uint lastPeriodDay = 7;
        uint startDate = block.timestamp;
        endDate = startDate + (totalDays * 1 days);
        uint currentStartDate = startDate;
        uint currentPrice = tokenPriceUSDT;

        for (uint i = 0; i < 13; i++) {
            stagePeriods.push(currentStartDate);
            currentStartDate += period * 1 days;
            priceStruct.push(currentPrice);
            currentPrice = (currentPrice * 110) / 100;
        }
        stagePeriods.push(currentStartDate);
        currentStartDate += shorterPeriodLength * 1 days;
        priceStruct.push(currentPrice);
        currentPrice = (currentPrice * 110) / 100;
        stagePeriods.push(currentStartDate);
        currentStartDate += lastPeriodDay * 1 days;
        priceStruct.push(currentPrice);
        stagePeriods.push(currentStartDate);
    }

    function startSale(bool _isSaleStart) external onlyOwner {
        if (isSaleStart == true) {
            revert("Sale alredy had started");
        }
        isSaleStart = _isSaleStart;
        initializeStages();
        emit SaleStarted(_isSaleStart);
    }

    function whichStage(uint8 _stage) internal {
        for (uint8 i = _stage; i < priceStruct.length; i++) {
            if (
                purchaseTokenContract.balanceOf(address(this)) >=
                constantValue * i
            ) {
                stage = i + 1;
                stagePeriods[i + 1] = 5 days + block.timestamp;
                tokenPriceUSDT = priceStruct[i];
            } else if (block.timestamp >= stagePeriods[i]) {
                stage = i + 1;
                tokenPriceUSDT = priceStruct[i];
            } else {
                break;
            }
        }
    }

    function ownerWithdrawPurchaseTokens() external nonReentrant onlyOwner {
        uint256 balance = purchaseTokenContract.balanceOf(address(this));
        require(balance > 0, "No tokens to withdraw");
        purchaseTokenContract.safeTransfer(receiverAddress, balance);
    }

    function ownerWithdrawETH() external nonReentrant onlyOwner {
        uint256 balanceContract = address(this).balance;
        require(balanceContract > 0, "No tokens to withdraw");
        (bool succes, ) = payable(msg.sender).call{value: balanceContract}("");
        require(succes, "Transact reverted");
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
        require(weiPerYourToken != 0, "Wei per token is zero");
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
        // Sending funds to a contract instead of sending them directly to the owner can provide an additional layer of security and control over the funds.
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

    function getStagePeriod() public view returns (uint, uint) {
        if (stage == 15) {
            return (stagePeriods[stage] - 7 days, stagePeriods[stage]);
        } else if (stage == 14) {
            return (stagePeriods[stage] - 4 days, stagePeriods[stage]);
        } else {
            return (stagePeriods[stage] - 5 days, stagePeriods[stage]);
        }
    }

    function toggleisSaleEnd(bool _isSaleEnd) public onlyOwner {
        isSaleEnd = _isSaleEnd;
    }

    function totalTokensBought(address account) public view returns (uint256) {
        return _tokensBought[account];
    }

    receive() external payable {}
}
