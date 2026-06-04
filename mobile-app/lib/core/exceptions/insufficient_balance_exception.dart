class InsufficientBalanceException implements Exception {
  final double currentBalance;
  final double transactionValue;
  final double estimatedGas;
  final double totalRequired;
  final double missingAmount;

  InsufficientBalanceException({
    required this.currentBalance,
    required this.transactionValue,
    required this.estimatedGas,
    required this.totalRequired,
    required this.missingAmount,
  });

  @override
  String toString() {
    return 'InsufficientBalanceException: Required $totalRequired ETH, but balance is $currentBalance ETH (Missing $missingAmount ETH)';
  }
}
