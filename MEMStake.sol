// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DoggyAiStake is Ownable {
    IERC20 public stakingToken;
    uint256 public rewardRate;
    bool isEarlyWithdral;
    uint256 public minStake = 10 * 10 ** 18;
    uint256 internal stakePeriod;
    uint256 public totalStaked;
    uint totalFund;

    event Staked(address indexed, uint256 amount);
    event Claimed(address indexed, uint256 amount);
    event Withdrawed(address indexed, uint256 amount);
    event PoolRefild(
        address indexed,
        uint256 amount,
        bool isEarlyWithdral,
        uint256 newStakePeriod,
        uint256 amountMinStake,
        uint256 rate
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
        rewardRate = 20;
        isEarlyWithdral = false;
        stakePeriod = _stakePeriod * 1 days;
        totalFund = 13800000000000000000000000000;
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
        Stake memory userStake = stakes[userAddress][stakeIndex];
        uint256 elapsedSeconds = block.timestamp - userStake.lastClaimTimestamp;
        if (userTotalStaked[msg.sender] == totalStaked) {
            return ((userStake.amount * elapsedSeconds * rewardRate) /
                (100 * stakePeriod));
        }
        uint baseReward = ((userStake.amount * elapsedSeconds * rewardRate) /
            (100 * stakePeriod));
        uint256 rewardAmount = (baseReward * userStake.amount) / totalStaked;
        return rewardAmount;
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

    function claimReward(uint256 stakeIndex) internal {
        stakes[msg.sender][stakeIndex].lastClaimTimestamp = block.timestamp;
        uint256 rewardAmount = calculateReward(msg.sender, stakeIndex);
        require(totalFund >= rewardAmount, "Staking is empty");
        require(
            stakingToken.transfer(msg.sender, rewardAmount),
            "Token transfer failed"
        );
        totalFund -= rewardAmount;
        emit Claimed(msg.sender, rewardAmount);
    }

    function claimAllRewards() external {
        require(isEarlyWithdral, "Early claim is not allowed");
        Stake[] memory userStakes = stakes[msg.sender];
        for (uint256 i; i < userStakes.length; i++) {
            claimReward(i);
        }
    }

    function withdraw() public {
        Stake[] storage userStake = stakes[msg.sender];
        uint i;
        for (i; i < userStake.length; i++) {
            require(isEarlyWithdral, "Early withdrawal is not allowed");

            uint256 rewardAmount = calculateReward(msg.sender, i);

            require(userStake[i].amount > 0, "Stake is empty");
            require(
                totalFund >= userStake[i].amount + rewardAmount,
                "Staking is empty"
            );

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
        }
    }

    function refilPool(
        uint256 amountToRefil,
        bool isLock,
        uint256 newStakePeriod,
        uint256 newMinStake,
        uint256 newProcent
    ) public onlyOwner {
        require(amountToRefil > 0, "Ammount to refil must be greater than 0");
        require(
            stakingToken.transferFrom(msg.sender, address(this), amountToRefil),
            "Your transaction is not valid"
        );
        toggleErlyWithdrawal(isLock);
        stakePeriod = newStakePeriod * 1 days;
        setMinStake(minStake);
        rewardRate = newProcent;
        emit PoolRefild(
            msg.sender,
            amountToRefil,
            isLock,
            newStakePeriod,
            newMinStake,
            newProcent
        );
    }

    function toggleErlyWithdrawal(bool _isEralyWithdrawal) public onlyOwner {
        isEarlyWithdral = _isEralyWithdrawal;
    }

    function setMinStake(uint256 newMinStake) public onlyOwner {
        minStake = newMinStake;
    }
}
