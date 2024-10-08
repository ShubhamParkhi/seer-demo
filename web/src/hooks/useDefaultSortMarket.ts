import { DEFAULT_CHAIN, SupportedChain } from "@/lib/chains";
import { bigIntMax } from "@/lib/utils";
import { useAccount } from "wagmi";
import { Market } from "./useMarket";
import { useAllOutcomePools } from "./useMarketPools";
import { defaultStatus, useVerificationStatusList } from "./useVerificationStatus";

const statusPriority = {
  verified: 0,
  verifying: 1,
  not_verified: 2,
};

type ExtendedMarket = Market & {
  creator?: string | null;
  liquidity?: bigint;
};

function useDefaultSortMarket(markets: Market[]) {
  const { address: currentUserAddress, chainId = DEFAULT_CHAIN } = useAccount();
  const { data: pools = [] } = useAllOutcomePools(chainId as SupportedChain);
  const { data: verificationStatusResultList } = useVerificationStatusList(chainId as SupportedChain);
  const outcomeLiquidityMapping = pools.reduce(
    (obj, item) => {
      const outcomeTokenId = item.token0.symbol === "sDAI" ? item.token1.id : item.token0.id;
      obj[outcomeTokenId.toLowerCase()] = BigInt(item.liquidity);
      return obj;
    },
    {} as { [key: string]: bigint },
  );
  return structuredClone(
    markets.map((market: ExtendedMarket) => {
      return {
        ...market,
        liquidity: bigIntMax(
          ...(market.wrappedTokens.map((address) => outcomeLiquidityMapping[address.toLowerCase()]) ?? []),
        ),
      };
    }),
  ).sort((a: ExtendedMarket, b: ExtendedMarket) => {
    // markets created by current user will show first
    const isACurrentUser = a.creator?.toLowerCase() === currentUserAddress?.toLowerCase();
    const isBCurrentUser = b.creator?.toLowerCase() === currentUserAddress?.toLowerCase();

    // If one is created by current user and the other isn't, prioritize the current user's item
    if (isACurrentUser && !isBCurrentUser) return -1;
    if (!isACurrentUser && isBCurrentUser) return 1;

    //by verification status
    const verificationStatusA = verificationStatusResultList?.[a.id.toLowerCase()] ?? defaultStatus;
    const verificationStatusB = verificationStatusResultList?.[b.id.toLowerCase()] ?? defaultStatus;
    const statusDiff = statusPriority[verificationStatusA.status] - statusPriority[verificationStatusB.status];
    if (statusDiff !== 0) {
      return statusDiff;
    }

    // by liquidity

    return a.liquidity === b.liquidity ? 0 : (b.liquidity ?? 0n) > (a.liquidity ?? 0n) ? 1 : -1;
  });
}

export default useDefaultSortMarket;
