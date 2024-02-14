import { MarketViewAbi } from "@/abi/MarketViewAbi";
import { DEFAULT_CHAIN, getConfigAddress } from "@/lib/config";
import { config } from "@/wagmi";
import { useQuery } from "@tanstack/react-query";
import { readContract } from "@wagmi/core";
import { Address } from "viem";
import { useAccount } from "wagmi";

export interface Question {
  content_hash: `0x${string}`;
  arbitrator: Address;
  opening_ts: number;
  timeout: number;
  finalize_ts: number;
  is_pending_arbitration: boolean;
  bounty: bigint;
  best_answer: `0x${string}`;
  history_hash: `0x${string}`;
  bond: bigint;
  min_bond: bigint;
}

export interface Market {
  id: Address;
  marketName: string;
  outcomes: readonly string[];
  conditionId: `0x${string}`;
  questionId: `0x${string}`;
  templateId: bigint;
  encodedQuestion: string;
  oracle: Address;
  pools: readonly Address[];
  question: Question;
}

export const useMarket = (marketId: Address) => {
  const { chainId = DEFAULT_CHAIN } = useAccount();

  return useQuery<Market | undefined, Error>({
    queryKey: ["useMarket", marketId],
    queryFn: async () => {
      return await readContract(config, {
        abi: MarketViewAbi,
        address: getConfigAddress("MARKET_VIEW", chainId),
        functionName: "getMarket",
        args: [getConfigAddress("CONDITIONAL_TOKENS", chainId), getConfigAddress("REALITIO", chainId), marketId],
        chainId,
      });
    },
  });
};
