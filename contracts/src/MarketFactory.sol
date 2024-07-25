/**
 *  @authors: []
 *  @reviewers: [@nvm1410]
 *  @auditors: []
 *  @bounties: []
 *  @deployments: []
 */

// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "./Market.sol";
import "./RealityProxy.sol";
import "./WrappedERC20Factory.sol";
import {IRealityETH_v3_0, IConditionalTokens} from "./Interfaces.sol";

contract MarketFactory {
    using Clones for address;

    // Workaround "stack too deep" errors
    struct CreateMarketParams {
        string marketName; // The name of the market
        string[] outcomes; // The market outcomes, doesn't include the INVALID_RESULT outcome
        string questionStart; // Used to build the Reality question on multi scalar markets
        string questionEnd; // Used to build the Reality question on multi scalar markets
        string outcomeType; // Used to build the Reality question on multi scalar markets
        string category; // Reality question category
        string lang; // Reality question language
        uint256 lowerBound; // Lower bound, only used for scalar markets
        uint256 upperBound; // Upper bound, only user for scalar markets
        uint256 minBond; // Min bond to use on Reality
        uint32 openingTime; // Reality question opening time
        string[] tokenNames; // Name of the ERC20 tokens associated to each outcome
    }

    // Workaround "stack too deep" errors
    struct InternalMarketConfig {
        bytes32 questionId; // Conditional Tokens questionId
        bytes32[] questionsIds; // Reality questions ids
        bytes32 conditionId; // Conditional Tokens conditionId
        uint256 outcomeSlotCount; // Conditional Tokens outcomeSlotCount
        uint256 templateId; // Reality templateId
    }

    uint8 internal constant REALITY_UINT_TEMPLATE = 1; // Template for scalar and multi scalar markets
    uint8 internal constant REALITY_SINGLE_SELECT_TEMPLATE = 2; // Template for categorical markets
    uint8 internal constant REALITY_MULTI_SELECT_TEMPLATE = 3; // Template for multi categorical markets

    uint32 public questionTimeout; // Reality question timeout

    address public immutable arbitrator; // Arbitrator contract
    IRealityETH_v3_0 public immutable realitio; // Reality.eth contract
    WrappedERC20Factory public immutable wrappedERC20Factory; // 1155 to 20 factory contract
    IConditionalTokens public immutable conditionalTokens; // Conditional Tokens contract
    address public immutable collateralToken; // Conditional Tokens collateral token contract
    RealityProxy public realityProxy; // Oracle contract
    address[] public markets; // Markets created by this factory
    address public market; // Market contract

    event NewMarket(
        address indexed market,
        string marketName,
        string[] outcomes,
        uint256 lowerBound,
        uint256 upperBound,
        bytes32 conditionId,
        bytes32 questionId,
        bytes32[] questionsIds,
        uint256 templateId,
        string[] encodedQuestions
    );

    /**
     *  @dev Constructor.
     *  @param _market Address of the market contract that is going to be used for each new deployment.
     *  @param _arbitrator Address of the arbitrator that is going to resolve Realitio disputes.
     *  @param _realitio Address of the Realitio implementation.
     *  @param _wrappedERC20Factory Address of the WrappedERC20Factory implementation.
     *  @param _conditionalTokens Address of the ConditionalTokens implementation.
     *  @param _collateralToken Address of the collateral token.
     *  @param _realityProxy Address of the RealityProxy implementation.
     *  @param _questionTimeout Reality question timeout.
     */
    constructor(
        address _market,
        address _arbitrator,
        IRealityETH_v3_0 _realitio,
        WrappedERC20Factory _wrappedERC20Factory,
        IConditionalTokens _conditionalTokens,
        address _collateralToken,
        RealityProxy _realityProxy,
        uint32 _questionTimeout
    ) {
        market = _market;
        arbitrator = _arbitrator;
        realitio = _realitio;
        wrappedERC20Factory = _wrappedERC20Factory;
        conditionalTokens = _conditionalTokens;
        collateralToken = _collateralToken;
        realityProxy = _realityProxy;
        questionTimeout = _questionTimeout;
    }

    function createCategoricalMarket(
        CreateMarketParams calldata params
    ) external returns (address) {
        require(params.outcomes.length >= 2, "Invalid outcomes count");

        uint256 outcomeSlotCount = params.outcomes.length + 1; // additional outcome for Invalid Result

        string[] memory encodedQuestions = new string[](1);
        encodedQuestions[0] = encodeRealityQuestionWithOutcomes(
            params.marketName,
            params.outcomes,
            params.category,
            params.lang
        );

        bytes32 questionId = askRealityQuestion(
            encodedQuestions[0],
            REALITY_SINGLE_SELECT_TEMPLATE,
            params.openingTime,
            params.minBond
        );

        bytes32 conditionId = prepareCondition(questionId, outcomeSlotCount);

        bytes32[] memory questionsIds = new bytes32[](1);
        questionsIds[0] = questionId;

        address marketId = createMarket(
            params,
            params.marketName,
            encodedQuestions,
            InternalMarketConfig({
                questionId: questionId,
                questionsIds: questionsIds,
                conditionId: conditionId,
                outcomeSlotCount: outcomeSlotCount,
                templateId: REALITY_SINGLE_SELECT_TEMPLATE
            })
        );

        return marketId;
    }

    function createMultiCategoricalMarket(
        CreateMarketParams calldata params
    ) external returns (address) {
        require(params.outcomes.length >= 2, "Invalid outcomes count");

        uint256 outcomeSlotCount = params.outcomes.length + 1; // additional outcome for Invalid Result

        string[] memory encodedQuestions = new string[](1);
        encodedQuestions[0] = encodeRealityQuestionWithOutcomes(
            params.marketName,
            params.outcomes,
            params.category,
            params.lang
        );

        bytes32 questionId = askRealityQuestion(
            encodedQuestions[0],
            REALITY_MULTI_SELECT_TEMPLATE,
            params.openingTime,
            params.minBond
        );

        bytes32 conditionId = prepareCondition(questionId, outcomeSlotCount);

        bytes32[] memory questionsIds = new bytes32[](1);
        questionsIds[0] = questionId;

        address marketId = createMarket(
            params,
            params.marketName,
            encodedQuestions,
            InternalMarketConfig({
                questionId: questionId,
                questionsIds: questionsIds,
                conditionId: conditionId,
                outcomeSlotCount: outcomeSlotCount,
                templateId: REALITY_MULTI_SELECT_TEMPLATE
            })
        );

        return marketId;
    }

    function createScalarMarket(
        CreateMarketParams calldata params
    ) external returns (address) {
        require(params.upperBound > params.lowerBound, "Invalid bounds");
        // values reserved by Reality for INVALID and UNRESOLVED_ANSWER
        require(
            params.upperBound < type(uint256).max - 2,
            "Invalid high point"
        );
        require(params.outcomes.length == 2, "Invalid outcomes count");

        uint256 outcomeSlotCount = 3; // additional outcome for Invalid Result

        string[] memory encodedQuestions = new string[](1);
        encodedQuestions[0] = encodeRealityQuestionWithoutOutcomes(
            params.marketName,
            params.category,
            params.lang
        );

        bytes32 questionId = askRealityQuestion(
            encodedQuestions[0],
            REALITY_UINT_TEMPLATE,
            params.openingTime,
            params.minBond
        );

        bytes32 conditionId = prepareCondition(questionId, outcomeSlotCount);

        bytes32[] memory questionsIds = new bytes32[](1);
        questionsIds[0] = questionId;

        address marketId = createMarket(
            params,
            params.marketName,
            encodedQuestions,
            InternalMarketConfig({
                questionId: questionId,
                questionsIds: questionsIds,
                conditionId: conditionId,
                outcomeSlotCount: outcomeSlotCount,
                templateId: REALITY_UINT_TEMPLATE
            })
        );

        return marketId;
    }

    function createMultiScalarMarket(
        CreateMarketParams calldata params
    ) external returns (address) {
        require(params.outcomes.length >= 2, "Invalid outcomes count");

        uint256 outcomeSlotCount = params.outcomes.length + 1; // additional outcome for Invalid Result

        bytes32[] memory questionsIds = new bytes32[](params.outcomes.length);

        string[] memory encodedQuestions = new string[](params.outcomes.length);

        for (uint256 i = 0; i < params.outcomes.length; i++) {
            encodedQuestions[i] = encodeRealityQuestionWithoutOutcomes(
                string(
                    abi.encodePacked(
                        params.questionStart,
                        params.outcomes[i],
                        params.questionEnd
                    )
                ),
                params.category,
                params.lang
            );

            questionsIds[i] = askRealityQuestion(
                encodedQuestions[i],
                REALITY_UINT_TEMPLATE,
                params.openingTime,
                params.minBond
            );
        }
        bytes32 questionId = keccak256(abi.encode(questionsIds));

        bytes32 conditionId = prepareCondition(questionId, outcomeSlotCount);

        address marketId = createMarket(
            params,
            string(
                abi.encodePacked(
                    params.questionStart,
                    params.outcomeType,
                    params.questionEnd
                )
            ),
            encodedQuestions,
            InternalMarketConfig({
                questionId: questionId,
                questionsIds: questionsIds,
                conditionId: conditionId,
                outcomeSlotCount: outcomeSlotCount,
                templateId: REALITY_UINT_TEMPLATE
            })
        );

        return marketId;
    }

    function createMarket(
        CreateMarketParams memory params,
        string memory marketName,
        string[] memory encodedQuestions,
        InternalMarketConfig memory config
    ) internal returns (address) {
        Market instance = Market(market.clone());

        deployERC20Positions(
            config.conditionId,
            config.outcomeSlotCount,
            params.tokenNames
        );
        instance.initialize(
            marketName,
            params.outcomes,
            params.lowerBound,
            params.upperBound,
            config.conditionId,
            config.questionId,
            config.questionsIds,
            config.templateId,
            encodedQuestions,
            realityProxy
        );

        emit NewMarket(
            address(instance),
            marketName,
            params.outcomes,
            params.lowerBound,
            params.upperBound,
            config.conditionId,
            config.questionId,
            config.questionsIds,
            config.templateId,
            encodedQuestions
        );
        markets.push(address(instance));

        return address(instance);
    }

    function encodeRealityQuestionWithOutcomes(
        string memory question,
        string[] calldata outcomes,
        string memory category,
        string memory lang
    ) internal pure returns (string memory) {
        bytes memory separator = abi.encodePacked(unicode"\u241f");

        bytes memory encodedOutcomes = abi.encodePacked('"', outcomes[0], '"');

        for (uint256 i = 1; i < outcomes.length; i++) {
            encodedOutcomes = abi.encodePacked(
                encodedOutcomes,
                ',"',
                outcomes[i],
                '"'
            );
        }

        return
            string(
                abi.encodePacked(
                    question,
                    separator,
                    encodedOutcomes,
                    separator,
                    category,
                    separator,
                    lang
                )
            );
    }

    function encodeRealityQuestionWithoutOutcomes(
        string memory question,
        string memory category,
        string memory lang
    ) internal pure returns (string memory) {
        bytes memory separator = abi.encodePacked(unicode"\u241f");

        return
            string(
                abi.encodePacked(question, separator, category, separator, lang)
            );
    }

    function askRealityQuestion(
        string memory question,
        uint256 templateId,
        uint32 openingTime,
        uint256 minBond
    ) internal returns (bytes32) {
        bytes32 content_hash = keccak256(
            abi.encodePacked(templateId, openingTime, question)
        );

        bytes32 question_id = keccak256(
            abi.encodePacked(
                content_hash,
                arbitrator,
                questionTimeout,
                minBond,
                address(realitio),
                address(this),
                uint256(0)
            )
        );

        if (realitio.getTimeout(question_id) != 0) {
            return question_id;
        }

        return
            realitio.askQuestionWithMinBond(
                templateId,
                question,
                arbitrator,
                questionTimeout,
                openingTime,
                0,
                minBond
            );
    }

    function prepareCondition(
        bytes32 questionId,
        uint outcomeSlotCount
    ) internal returns (bytes32) {
        conditionalTokens.prepareCondition(
            address(realityProxy),
            questionId,
            outcomeSlotCount
        );

        return
            conditionalTokens.getConditionId(
                address(realityProxy),
                questionId,
                outcomeSlotCount
            );
    }

    function deployERC20Positions(
        bytes32 conditionId,
        uint256 outcomeSlotCount,
        string[] memory tokenNames
    ) internal {
        uint256 invalidResultIndex = outcomeSlotCount - 1;

        for (uint j = 0; j < outcomeSlotCount; j++) {
            bytes32 collectionId = conditionalTokens.getCollectionId(
                bytes32(0),
                conditionId,
                1 << j
            );
            uint256 tokenId = conditionalTokens.getPositionId(
                collateralToken,
                collectionId
            );

            require(
                j == invalidResultIndex || bytes(tokenNames[j]).length != 0,
                "Missing token name"
            );

            wrappedERC20Factory.createWrappedToken(
                address(conditionalTokens),
                tokenId,
                j == invalidResultIndex ? "SEER_INVALID_RESULT" : tokenNames[j],
                j == invalidResultIndex ? "SEER_INVALID_RESULT" : tokenNames[j]
            );
        }
    }

    function allMarkets() external view returns (address[] memory) {
        return markets;
    }

    function marketCount() external view returns (uint256) {
        return markets.length;
    }
}
