import 'package:flutter/material.dart';

class BusinessDetailScreen extends StatelessWidget {
  final String businessId;

  const BusinessDetailScreen({
    super.key,
    required this.businessId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Business Details'),
      ),
      body: Center(
        child: Text('Business ID: $businessId\n\nDetails coming soon!'),
      ),
    );
  }
}
