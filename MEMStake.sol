// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract DoggyAiStake is Ownable, ReentrancyGuard {
    IERC20 public stakingToken;
    bool public isEarlyWithdrawal;
    uint256 public minStake = 10 * 10 ** 18;
    uint256 public stakePeriod;
    uint256 public totalStaked;
    uint public constantTotalFunds;
    uint public totalFund;
    uint public rewardRate;

    event Staked(address indexed, uint256 amount);
    event Claimed(address indexed, uint256 amount);
    event Withdrawed(address indexed, uint256 amount);
    event PoolRefild(
        address indexed,
        uint256 amount,
        bool isEarlyWithdral,
        uint256 newStakePeriod,
        uint256 amountMinStake
    );

    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 lastClaimTimestamp;
    }

    mapping(address => uint256) public userTotalStaked;
    mapping(address => Stake[]) public stakes;

    modifier _checkRewardRate() {
        if (totalStaked == 0) {
            rewardRate = ((totalFund / stakePeriod) / minStake);
        } else {
            rewardRate = ((totalFund / stakePeriod) / totalStaked);
        }
        _;
    }

    constructor(
        address DoggyAi,
        address initialOwner,
        uint256 _stakePeriod,
        uint amountToFill
    ) Ownable(initialOwner) {
        stakingToken = IERC20(DoggyAi);
        isEarlyWithdrawal = false;
        stakePeriod = _stakePeriod * 1 days;
        constantTotalFunds = amountToFill;
        totalFund = constantTotalFunds;
        rewardRate = ((totalFund / stakePeriod) / 10);
    }

    function getStakes(
        address user,
        uint stakesIndex
    ) public view returns (Stake memory) {
        return stakes[user][stakesIndex];
    }

    function calculateReward(
        address userAddress,
        uint256 stakeIndex
    ) public view returns (uint256) {
        Stake storage userStake = stakes[userAddress][stakeIndex];
        uint256 elapsedSeconds = block.timestamp - userStake.lastClaimTimestamp;
        return (userStake.amount * elapsedSeconds * rewardRate);
    }

    function getUserStakes(
        address userAddress
    ) external view returns (Stake[] memory userStakes) {
        return stakes[userAddress];
    }

    function stake(uint256 _amount) public _checkRewardRate {
        require(
            _amount >= minStake,
            "The amount must be greater than minimum 10 tokens"
        );

        userTotalStaked[msg.sender] += _amount;
        stakes[msg.sender].push(
            Stake(_amount, block.timestamp, block.timestamp)
        );
        require(
            stakingToken.transferFrom(msg.sender, address(this), _amount),
            "Token transfer failed"
        );
        totalStaked += _amount;
        emit Staked(msg.sender, _amount);
    }

    function calculatePoolProcentage() external view returns (uint256) {
        return (totalFund / constantTotalFunds) * 100;
    }

    function claimReward(uint256 stakeIndex) internal {
        Stake storage userStake = stakes[msg.sender][stakeIndex];
        uint256 rewardAmount = calculateReward(msg.sender, stakeIndex);

        require(rewardAmount > 0, "No reward available");
        require(rewardAmount <= totalFund, "Not enough funds in contract");

        userStake.lastClaimTimestamp = block.timestamp;

        require(
            stakingToken.transfer(msg.sender, rewardAmount),
            "Token transfer failed"
        );

        totalFund -= rewardAmount;

        emit Claimed(msg.sender, rewardAmount);
    }

    function claimAllRewards() external nonReentrant {
        require(isEarlyWithdrawal, "Early claim is not allowed");
        Stake[] memory userStakes = stakes[msg.sender];
        for (uint256 i; i < userStakes.length; i++) {
            rewardRate = ((totalFund / stakePeriod) / totalStaked);
            claimReward(i);
        }
    }

    function claimAndStake() public nonReentrant {
        require(isEarlyWithdrawal, "Early claim is not allowed");
        Stake[] storage userStakes = stakes[msg.sender];
        for (uint256 i; i < userStakes.length; i++) {
            uint reward = calculateReward(msg.sender, i);
            require(
                reward >= minStake,
                "The amount must be greater than minimum 10 tokens"
            );
            require(reward > 0, "No reward available");
            require(reward <= totalFund, "Not enough funds in contract");
            userStakes[i].amount += reward;
        }
    }

    function withdraw() public nonReentrant _checkRewardRate {
        Stake[] storage userStake = stakes[msg.sender];
        uint i;
        for (i; i < userStake.length; i++) {
            if (userStake[i].amount <= 0) {
                revert("The amount must be greater than minimum 10 tokens");
            }
            require(isEarlyWithdrawal, "Early withdrawal is not allowed");
            rewardRate = ((totalFund / stakePeriod) / totalStaked);
            uint256 rewardAmount = calculateReward(msg.sender, i);
            require(
                stakingToken.transfer(
                    msg.sender,
                    userStake[i].amount + rewardAmount
                ),
                "Token transfer failed"
            );
            userTotalStaked[msg.sender] -= userStake[i].amount;
            totalStaked -= userStake[i].amount;
            totalFund -= rewardAmount;
            userStake[i].amount = 0;
            emit Withdrawed(msg.sender, userStake[i].amount + rewardAmount);
            delete stakes[msg.sender];
        }
    }

    function refillPool(
        uint256 amountToRefil,
        bool isLock,
        uint256 newStakePeriod,
        uint256 newMinStake
    ) public onlyOwner {
        require(
            newStakePeriod > 0,
            "New stake period should be greater than 0"
        );
        require(amountToRefil > 0, "Ammount to refil must be greater than 0");
        require(
            stakingToken.transferFrom(msg.sender, address(this), amountToRefil),
            "Your transaction is not valid"
        );
        toggleEarlyWithdrawal(isLock);
        stakePeriod = newStakePeriod * 1 days;
        setMinStake(minStake);
        constantTotalFunds = amountToRefil;
        totalFund = constantTotalFunds;
        if (totalStaked == 0) {
            rewardRate = ((totalFund / stakePeriod) / minStake);
            emit PoolRefild(
                msg.sender,
                amountToRefil,
                isLock,
                newStakePeriod,
                newMinStake
            );
        } else {
            rewardRate = ((totalFund / stakePeriod) / totalStaked);
            emit PoolRefild(
                msg.sender,
                amountToRefil,
                isLock,
                newStakePeriod,
                newMinStake
            );
        }
    }

    function toggleEarlyWithdrawal(bool _isEralyWithdrawal) public onlyOwner {
        isEarlyWithdrawal = _isEralyWithdrawal;
    }

    function setMinStake(uint256 newMinStake) public onlyOwner {
        minStake = newMinStake;
    }
}
