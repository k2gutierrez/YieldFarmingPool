// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title Abi Encoder Library
 * @author Carlos Gutiérrez
 * @notice This smart contract show different uses of abi.encodePacked in DeFi protocols
 */
library AbiEncoder {
    
    // Events to show the codification
    event DataEncoded(bytes32 indexed hash, bytes encodedData);
    event PoolIdentifierCreated(bytes32 indexed userId, address token, uint256 rate);
    event UserPositionEncoded(bytes32 indexed positionId, address user, uint256 amount);

    /**
     * 
     * @dev This function encodes the pool parameters
     * @param _tokenA first pool token
     * @param _tokenB second pool token
     * @param _fee pool fee
     * @return poolId identifier (unique for this pool)
     */
    function createPoolIdentifier(address _tokenA, address _tokenB, uint24 _fee) external pure returns(bytes32 poolId){


        // We order the tokens
        (address token0, address token1) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);

        // Use of ABI.ENCODEPACKED: Create unique pool identifier
        poolId = keccak256(abi.encodePacked(token0, token1, _fee));

    }

    /**
     * @dev Encodes data for a trading position
     * @param _user User address
     * @param _tokenIn Input token
     * @param _tokenOut Output token
     * @param _amountIn Input amount
     * @param _minAmountOut Minimum output amount expected to receive
     * @return positionId Positiion identifier
     * @return encodedData Encoded position data
     */
    function encodeTradingPosition(address _user, address _tokenIn, address _tokenOut, uint256 _amountIn, uint256 _minAmountOut, uint256 _deadline) external pure returns(bytes32 positionId, bytes memory encodedData) {
        // Encode the position data
        encodedData = abi.encodePacked(_user, _tokenIn, _tokenOut, _amountIn, _minAmountOut, _deadline);

        // Create unique identifier for the position
        positionId = keccak256(encodedData);

    }

    /**
     * @dev Encodes parameters for a swap on a DEX
     * @param _path Array of tokens for the swap
     * @param _amount Array of amount
     * @param _deadline transaction deadline
     * @return swapData Encoded swap data
     */
    function encodeSwapData(address[] calldata _path, uint256[] calldata _amount, uint256 _deadline) external pure returns(bytes memory swapData) {

        require(_path.length == _amount.length, "Array length mismatch");

        // Encode the path
        bytes memory pathData;
        for (uint i; i < _path.length; i++) {
            pathData = abi.encodePacked(pathData, _path[i]);
        }

        // Encode the amounts
        bytes memory amountData;
        for (uint i; i < _path.length; i++) {
            amountData = abi.encodePacked(amountData, _amount[i]);
        }

        // Combine everything
        swapData = abi.encodePacked(pathData, amountData, _deadline);

    }

    /**
     * @dev Encodes data for a limit order
     * @param _maker Maker address
     * @param _taker Taker address
     * @param _tokenIn Input token
     * @param _tokenOut Output token
     * @param _amountIn Input amount
     * @param _amountOut Output amount
     * @param _nonce Unique nonce
     * @return orderHash Order hash
     * @return orderData Encoded order data
     */
    function encodeLimitOrder(address _maker, address _taker, address _tokenIn, address _tokenOut, uint256 _amountIn, uint256 _amountOut, uint256 _nonce) external pure returns(bytes32 orderHash, bytes memory orderData) {
        // Encode the order data
        orderData = abi.encodePacked(_maker, _taker, _tokenIn, _tokenOut, _amountIn, _amountOut, _nonce, "LIMIT_ORDER_V1");

        orderHash = keccak256(orderData);

    }

    /**
     * @dev Encodes data for a yield farming position
     * @param _user User address
     * @param _poolId Pool identifier
     * @param _amount Stacked amount
     * @param _startTime Start time
     * @return positionId Position identifier
     */
    function encodeYieldPosition(address _user, bytes32 _poolId, uint256 _amount, uint256 _startTime) external pure returns(bytes32 positionId) {
        positionId = keccak256(abi.encodePacked(_user, _poolId, _amount, _startTime, "YIELD_POSITION"));
    }

    /**
     * @dev Encode data for a flashloan token
     * @param _token Flashloan token
     * @param _amount Loan amount
     * @param callBackData Callback data
     * @return flashData Encoded flash loan data
     */
    function encodeFlashLoanData(address _token, uint256 _amount, bytes calldata callBackData) external pure returns(bytes memory flashData) {
        flashData = abi.encodePacked(_token, _amount, callBackData, "FLASH_LOAN_V1");
    }

    /**
     * @dev Encodes parameters for a staking pool
     * @param _token token address
     * @param _rewardRate Reward rate
     * @param _lockPeriod Lock period
     * @param maxStakers Maximum number of stakers
     * @return poolConfig Encoded configuration data
     */
    function encodeStakingPoolConfig(address _token, uint256 _rewardRate, uint256 _lockPeriod, uint256 maxStakers) external view returns(bytes memory poolConfig) {
        poolConfig = abi.encodePacked(_token, _rewardRate, _lockPeriod, maxStakers, block.timestamp);
    }

    function encodeCreatePoolId(address token, uint256 rewardRate) external view returns(bytes32 poolId) {
        poolId = keccak256(abi.encodePacked(
            token,
            rewardRate,
            block.timestamp,
            block.chainid
        ));
    }

    function poolEncodedData(
        address token,
        uint256 totalStaked,
        uint256 rewardRate,
        uint256 lastUpdateTime,
        uint256 rewardPerTokenStored,
        bool isActive
    ) external pure returns(bytes memory encodedData) {
        encodedData = abi.encodePacked(
            token,
            totalStaked,
            rewardRate,
            lastUpdateTime,
            rewardPerTokenStored,
            isActive
        );
    }

    function encodeUserHash(bytes32 poolId, address user) external pure returns(bytes32 userHash) {
        userHash = keccak256(abi.encodePacked(poolId, user, "YIELD_FARMING_USER"));
    }

    /**
     * @dev Creates a unique hash for a user on multiple pools
     * @param _user User address
     * @param poolIds Array of pool identifiers
     * @return userHash Unique user hash
     */
    function createUserMultiPullHash(address _user, bytes32[] calldata poolIds) external pure returns (bytes32 userHash) {
        bytes memory data = abi.encodePacked(_user);

        for (uint i = 0; i < poolIds.length; i++) {
            data = abi.encodePacked(data, poolIds[i]);
        }

        data = abi.encodePacked(data, "MULTI_POOL_USER");
        userHash = keccak256(data);
    }

    /**
     * @dev Encode data for a yield farming strategy
     * @param strategyName Name of the strategy
     * @param pools Array of involved pools
     * @param weights Array of weights for each pool
     * @return strategyData Encoded strategy data
     */
    function encodeYieldStrategy(
        string calldata strategyName, 
        address[] calldata pools, 
        uint256[] calldata weights
    ) external pure returns(bytes memory strategyData) {
        require(pools.length == weights.length, "Arrays length mismatch");

        // Encode strategy name
        bytes memory nameData = abi.encodePacked(strategyName);

        // Encode pools
        bytes memory poolsData;
        for (uint i = 0; i < pools.length; i++) {
            poolsData = abi.encodePacked(poolsData, pools[i]);
        }

        // Encode weights
        bytes memory weightsData;
        for (uint i = 0; i < weights.length; i++) {
            weightsData = abi.encodePacked(weightsData, weights[i]);
        }

        // Combine everything
        strategyData = abi.encodePacked(
            nameData,
            poolsData,
            weightsData,
            "YIELD_STRATEGY_V1"
        );

    }

    /**
     * @dev Demonstrates encoding data for a cross-chain bridge
     * @param sourceChain Source chain
     * @param targetChain Target chain
     * @param token Token to transfer
     * @param amount Amount
     * @param recipient Encoded bridge data
     * @return bridgeData Endoded bridge data
     */
    function encodeCrossChainBridgeData(
        uint256 sourceChain,
        uint256 targetChain,
        address token,
        uint256 amount,
        address recipient
    ) external pure returns(bytes memory bridgeData) {
        bridgeData = abi.encodePacked(
            sourceChain,
            targetChain,
            token,
            amount,
            recipient,
            "CROSS_CHAIN_BRIDGE"
        );
    }

    /**
     * @dev Creates unique identifier for a DeFi transaction
     * @param txType Transaction type
     * @param user User
     * @param timestamp Timestamp
     * @param nonce Unique nonce
     * @return txId Transaction Id hash
     */
    function createDefiTransactionId(
        string calldata txType,
        address user,
        uint256 timestamp,
        uint256 nonce
    ) external pure returns(bytes32 txId) {
        txId = keccak256(
            abi.encodePacked(
                txType,
                user,
                timestamp,
                nonce,
                "DEFI_TX"
            )
        );
    }

    /**
     * @dev Encode data for a stop loss order
     * @param user User address
     * @param token Token to sell
     * @param amount Amount to sell
     * @param stopPrice Stop loss price
     * @param triggerPrice Trigger price
     * @return stopLossData Encoded order data
     */
    function encodeStopLossOrder(
        address user,
        address token,
        uint256 amount,
        uint256 stopPrice,
        uint256 triggerPrice
    ) external pure returns(bytes memory stopLossData) {
        stopLossData = abi.encodePacked(
            user,
            token,
            amount,
            stopPrice,
            triggerPrice,
            "STOP_LOSS_ORDER"
        );
    }

    /**
     * @dev Encodes data for a take profit order
     * @param user User address
     * @param token Token to seel
     * @param amount Amount to sell
     * @param takeProfitPrice Take profit price
     * @return takeProfitData Encoded order data
     */
    function encodeTakeProfitOrder(
        address user,
        address token,
        uint256 amount,
        uint256 takeProfitPrice
    ) external pure returns(bytes memory takeProfitData) {
        takeProfitData = abi.encodePacked(
            user,
            token,
            amount,
            takeProfitPrice,
            "TAKE_PROFIT_ORDER"
        );
    }

    /**
     * @dev Encodes data for a trailing stop order
     * @param user User address
     * @param token Token to sell
     * @param amount Amount to sell
     * @param trailingPercent Trailing percentage
     * @param activationPrice Activation price
     * @return trailingStopData Encoded order data
     */
    function encodeTrailingStopOrder(
        address user,
        address token,
        uint256 amount,
        uint256 trailingPercent,
        uint256 activationPrice
    ) external pure returns(bytes memory trailingStopData) {
        trailingStopData = abi.encodePacked(
            user,
            token,
            amount,
            trailingPercent,
            activationPrice,
            "TRAILING_STOP_ORDER"
        );
    }

}
