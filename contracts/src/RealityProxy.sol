// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IConditionalTokens, IRealityETH_v3_0} from "./Interfaces.sol";

contract RealityProxy {
    IConditionalTokens public conditionalTokens;
    IRealityETH_v3_0 public realitio;

    constructor(
        IConditionalTokens _conditionalTokens,
        IRealityETH_v3_0 _realitio
    ) {
        conditionalTokens = _conditionalTokens;
        realitio = _realitio;
    }

    function resolveCategoricalMarket(
        bytes32 questionId,
        uint256 templateId,
        uint256 numOutcomes
    ) external {
        uint256[] memory payouts;

        if (templateId == 0 || templateId == 2) {
            // binary or single-select
            payouts = getSingleSelectPayouts(questionId, numOutcomes);
        } else {
            revert("Unknown templateId");
        }

        conditionalTokens.reportPayouts(questionId, payouts);
    }

    function resolveScalarMarket(
        bytes32 questionId,
        uint256 low,
        uint256 high
    ) external {
        require(low < high, "Range invalid");
        require(high != type(uint256).max, "Invalid high point");

        uint256[] memory payouts = new uint256[](2);

        uint256 answer = uint256(realitio.resultForOnceSettled(questionId));

        if (answer == type(uint256).max) {
            payouts[0] = 1;
            payouts[1] = 1;
        } else if (answer <= low) {
            payouts[0] = 1;
            payouts[1] = 0;
        } else if (answer >= high) {
            payouts[0] = 0;
            payouts[1] = 1;
        } else {
            payouts[0] = high - answer;
            payouts[1] = answer - low;
        }

        conditionalTokens.reportPayouts(
            keccak256(abi.encode(questionId, low, high)),
            payouts
        );
    }

    function resolveMultiScalarMarket(
        bytes32 questionId,
        bytes32[] memory questionsIds,
        uint256 numOutcomes
    ) external {
        uint256[] memory payouts = new uint256[](numOutcomes);

        for (uint i = 0; i < numOutcomes; i++) {
            payouts[i] = uint256(
                realitio.resultForOnceSettled(questionsIds[i])
            );
        }

        conditionalTokens.reportPayouts(questionId, payouts);
    }

    function getSingleSelectPayouts(
        bytes32 questionId,
        uint256 numOutcomes
    ) internal view returns (uint256[] memory) {
        uint256[] memory payouts = new uint256[](numOutcomes);

        uint256 answer = uint256(realitio.resultForOnceSettled(questionId));

        if (answer == type(uint256).max) {
            for (uint256 i = 0; i < numOutcomes; i++) {
                payouts[i] = 1;
            }
        } else {
            require(
                answer < numOutcomes,
                "Answer must be between 0 and numOutcomes"
            );
            payouts[answer] = 1;
        }

        return payouts;
    }
}
