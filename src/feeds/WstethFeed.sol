// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

interface IChainlinkFeed {
    function latestRoundData() external view
    returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
    function decimals() external view returns (uint8);
}

interface IWstETH {
    function stEthPerToken() external view returns (uint256);
}

contract WstethFeed {

    uint8 public immutable decimals;
    IWstETH public immutable wsteth;
    IChainlinkFeed public immutable stethFeed;
    IChainlinkFeed public immutable ethFeed;

    constructor(address _stethFeed, address _ethFeed, address _wsteth) {
        stethFeed = IChainlinkFeed(_stethFeed);
        ethFeed = IChainlinkFeed(_ethFeed);
        require(stethFeed.decimals() == ethFeed.decimals(), "decimals mismatch");
        wsteth = IWstETH(_wsteth);
        decimals = stethFeed.decimals();
    }

    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        (   
            roundId,
            answer,
            startedAt,
            updatedAt,
            answeredInRound
        ) = stethFeed.latestRoundData();
        (, int256 ethPrice, , ,) = ethFeed.latestRoundData();
        // use the min of the two prices. stETH can't be worth more than ETH
        answer = ethPrice < answer && ethPrice > 0 ? ethPrice : answer;
        answer = answer * int256(wsteth.stEthPerToken()) / 1e18; // 1e18 is the decimals of stEthPerToken
    }
}