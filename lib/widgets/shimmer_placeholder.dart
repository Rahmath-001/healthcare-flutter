import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class ShimmerPlaceholder extends StatelessWidget {
  final Widget child;

  const ShimmerPlaceholder({super.key, required this.child});

  factory ShimmerPlaceholder.line({double width = 120, double height = 14}) {
    return ShimmerPlaceholder(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  factory ShimmerPlaceholder.circle({double radius = 24}) {
    return ShimmerPlaceholder(
      child: CircleAvatar(radius: radius, backgroundColor: Colors.white),
    );
  }

  factory ShimmerPlaceholder.rect(
      {double width = double.infinity, double height = 48}) {
    return ShimmerPlaceholder(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: child,
    );
  }
}
