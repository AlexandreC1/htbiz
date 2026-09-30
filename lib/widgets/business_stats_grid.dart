import 'package:flutter/material.dart';

class BusinessStat {
  const BusinessStat(this.icon, this.value, this.label);
  final IconData icon;
  final String value;
  final String label;
}

class BusinessStatsGrid extends StatelessWidget {
  const BusinessStatsGrid({super.key, required this.stats});
  final List<BusinessStat> stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final columns = MediaQuery.textScalerOf(context).scale(14) > 21
          ? 1
          : constraints.maxWidth >= 600
              ? 4
              : 2;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(spacing: 12, runSpacing: 12, children: [
        for (final stat in stats)
          SizedBox(
            width: width,
            child: Semantics(
              label: '${stat.label}: ${stat.value}',
              child: ExcludeSemantics(
                  child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(stat.icon, color: theme.colorScheme.primary),
                      const SizedBox(height: 8),
                      Text(stat.value,
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(stat.label, style: theme.textTheme.bodyMedium),
                    ]),
              )),
            ),
          ),
      ]);
    });
  }
}
