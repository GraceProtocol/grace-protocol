// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

interface IAPI3 {
    function read() external view returns (int224 value, uint32 timestamp);
}

contract API3Feed {

    uint8 public constant decimals = 18;
    IAPI3 public immutable feed;

    constructor(address _feed) {
        feed = IAPI3(_feed);
    }

   function latestRoundData() external view
   returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
      (answer, updatedAt) = feed.read();
      startedAt = updatedAt;
      roundId = 1;
      answeredInRound = 1;
    }

    function latestAnswer() external view returns (int256 value) {
       (value, ) = feed.read();
   }

}