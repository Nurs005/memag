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
    uint256 public price;
    uint256 public minPurchaseAmount = 1;
    uint48 startTime;
    uint8 public stage = 1;
    IUniswapV3Pool private pool;

    mapping(address => uint256) private _tokensBought;
    mapping(address => uint256) private _lastClaimTime;

    event BuyTokens(address indexed addr, uint256 amount);
    event SaleStatusChanged(bool newStatus);
    event PriceUpdated(uint256 newPrice);
    event MinPurchaseAmountChanged(uint256 newMinPurchaseAmount);

    struct StagePrices {
        uint256[] prices;
    }

    struct StageBalances {
        uint256[] balansec;
    }

    StagePrices priceStruct;
    StageBalances blanceStruct;

    constructor(
        address initialOwner,
        address DoggyAi,
        address stableToken,
        address pools
    ) Ownable(initialOwner) {
        tokenContract = IERC20(DoggyAi);
        purchaseTokenContract = IERC20(stableToken);
        receiverAddress = initialOwner;
        price = 2888;
        startTime = uint48(block.timestamp);
        pool = IUniswapV3Pool(pools);
        initializeStages();
    }

    function initializeStages() internal {
        uint length = 15;
        priceStruct.prices = new uint[](length);
        blanceStruct.balansec = new uint[](length);

        for (uint8 i = 0; i < length; i++) {
            require(
                i < priceStruct.prices.length &&
                    i < blanceStruct.balansec.length,
                "Index out of bounds"
            );

            if (i == 0) {
                priceStruct.prices[i] = price;
                blanceStruct.balansec[i] = 0;
            } else {
                unchecked {
                    priceStruct.prices[i] =
                        (priceStruct.prices[i - 1] * 110) /
                        100 +
                        1;
                }
                blanceStruct.balansec[i] =
                    blanceStruct.balansec[i - 1] +
                    714285710000000000000;
            }
        }
    }

    function whichStage(uint8 _stage) public {
        for (uint8 i = _stage - 1; i < priceStruct.prices.length; i++)
            if (
                purchaseTokenContract.balanceOf(address(this)) >=
                blanceStruct.balansec[i]
            ) {
                stage = i + 1;
                price = priceStruct.prices[i];
            }
    }

    function getStages() public view returns (uint256[] memory) {
        return priceStruct.prices;
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

    function setPrice(uint256 _newPrice) public onlyOwner {
        require(_newPrice > 0, "Price cannot be zero");
        price = _newPrice;
        emit PriceUpdated(_newPrice);
    }

    function setMinPurchaseAmount(
        uint256 _newMinPurchaseAmount
    ) external onlyOwner {
        require(_newMinPurchaseAmount > 0, "Amount cannot be zero");
        minPurchaseAmount = _newMinPurchaseAmount;
        emit MinPurchaseAmountChanged(_newMinPurchaseAmount);
    }

    function calculatePrice(uint256 amount) public view returns (uint256) {
        uint count = amount / 10 ** 18;
        uint256 countOfPurchaseTokens = ((1e18 * price) * count) / 10 ** 18;
        return countOfPurchaseTokens;
    }

    function calculatePriceWEI(uint amountToken) public view returns (uint256) {
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
        uint256 weiPerYourToken = FullMath.mulDiv(price, weiPerUSDT, 1e6);
        uint256 totalWei = FullMath.mulDiv(amountToken, weiPerYourToken, 1);
        return totalWei / 1e18;
    }

    function buyTokens(uint256 tokenAmount) public payable nonReentrant {
        require(!isSaleEndTime, "Sale has ended");
        require(
            tokenAmount >= minPurchaseAmount,
            "Token amount is below the minimum purchase amount"
        );
        require(tokenAmount > 0, "Insufficient purchase token to buy tokens");
        require(
            tokenAmount <= tokenContract.balanceOf(address(this)),
            "Insufficient tokens in contract"
        );
        require(price > 0, "Price not set");
        whichStage(stage);

        if (msg.value != 0) {
            (bool succes, ) = payable(address(this)).call{
                value: calculatePriceWEI(tokenAmount)
            }("");
            if (!succes) {
                revert("Transfer eth error");
            }
        }

        uint256 countOfPurchaseTokens = calculatePrice(tokenAmount);

        purchaseTokenContract.safeTransferFrom(
            msg.sender,
            address(this),
            countOfPurchaseTokens
        );
        require(
            tokenContract.transfer(msg.sender, tokenAmount),
            "Tranfer failed"
        );

        _tokensBought[msg.sender] += tokenAmount;
        emit BuyTokens(msg.sender, tokenAmount);
    }

    function totalTokensBought(address account) public view returns (uint256) {
        return _tokensBought[account];
    }
}
