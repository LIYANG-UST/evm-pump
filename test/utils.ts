export const getDomainStruct = (chainId: number, verifyingContract: string) => {
  return {
    name: "BoosterTreasury",
    version: "1.0",
    chainId: chainId,
    verifyingContract: verifyingContract,
  };
};
