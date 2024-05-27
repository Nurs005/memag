// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract DoggyAiStake is Ownable, ReentrancyGuard {
    IERC20 public stakingToken;
    bool isEarlyWithdrawal;
    uint256 public minStake = 10 * 10 ** 18;
    uint256 internal stakePeriod;
    uint256 public totalStaked;
    uint public constantTotalFunds;
    uint public totalFund;

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
    mapping(address => Stake[]) private stakes;

    constructor(
        address DoggyAi,
        address initialOwner,
        uint256 _stakePeriod
    ) Ownable(initialOwner) {
        stakingToken = IERC20(DoggyAi);
        isEarlyWithdrawal = false;
        stakePeriod = _stakePeriod * 1 days;
        constantTotalFunds = 13800000000000000000000000000;
        totalFund = constantTotalFunds;
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
        uint rewardRate = ((totalFund / stakePeriod) / totalStaked);
        return (userStake.amount * elapsedSeconds * rewardRate);
    }

    function getUserStakes(
        address userAddress
    ) external view returns (Stake[] memory userStakes) {
        return stakes[userAddress];
    }

    function stake(uint256 _amount) public {
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

    function calculatePoolProcentage() public view returns (uint256) {
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
            claimReward(i);
        }
    }

    function withdraw() public nonReentrant {
        Stake[] storage userStake = stakes[msg.sender];
        uint i;
        for (i; i < userStake.length; i++) {
            if (userStake[i].amount <= 0) {
                revert("The amount must be greater than minimum 10 tokens");
            }
            require(isEarlyWithdrawal, "Early withdrawal is not allowed");
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
            delete stakes[msg.sender];
            emit Withdrawed(msg.sender, userStake[i].amount + rewardAmount);
        }
    }

    function refilPool(
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
        emit PoolRefild(
            msg.sender,
            amountToRefil,
            isLock,
            newStakePeriod,
            newMinStake
        );
    }

    function toggleEarlyWithdrawal(bool _isEralyWithdrawal) public onlyOwner {
        isEarlyWithdrawal = _isEralyWithdrawal;
    }

    function setMinStake(uint256 newMinStake) public onlyOwner {
        minStake = newMinStake;
    }
}
