const args_abi = [
  "address", // ChainlinkVRFCoordinator address
  "uint64", // ChainlinkVRFSubscriptionId
  "bytes32", // ChainlinkKeyHash
  "uint256", // Muon appId
  "tuple(uint256 x, uint8 parity) d", // Muon publicKey
  "address", // Muon address
  "address", // Admin
  "address" // Operator
]

const args_values = [
  "0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625",
  2383,
  "0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c",
  "25465578003500666162514846212575646525905546121357887312364528382074876315425",
  {
    x: "0x701bdf32d0b912560fd66d60723f49caf1ec3e41a727eeb31124f653a9987e3b",
    parity: 1,
  },
  "0x47206B40a0cfab6D8663D887A20c9398beB35f64",
  "0xb57490CDAABEDb450df33EfCdd93079A24ac5Ce5",
  "0xB10f8E218A9cD738b0F1E2f7169Aa3c0897F2d83"
]

// const args_abi = [
//   "uint256", // Muon appId
//   "tuple(uint256 x, uint8 parity) d", // Muon publicKey
// ]

// const args_values = [
//   "25465578003500666162514846212575646525905546121357887312364528382074876315425",
//   {
//     x: "0x701bdf32d0b912560fd66d60723f49caf1ec3e41a727eeb31124f653a9987e3b",
//     parity: 1,
//   }
// ]

module.exports = {
  args_abi, args_values
}