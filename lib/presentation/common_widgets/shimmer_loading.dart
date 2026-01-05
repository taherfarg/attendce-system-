import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ShimmerList extends StatelessWidget {
  final int itemCount;
  final double height;

  const ShimmerList({super.key, this.itemCount = 5, this.height = 80});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: itemCount,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemBuilder: (context, index) {
        return Container(
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(10),
                ),
              )
                  .animate(onPlay: (c) => c.repeat())
                  .shimmer(duration: 1200.ms, color: Colors.grey.shade50),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 120,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ).animate(onPlay: (c) => c.repeat()).shimmer(
                        duration: 1200.ms,
                        delay: 200.ms,
                        color: Colors.grey.shade50),
                    const SizedBox(height: 8),
                    Container(
                      width: 80,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ).animate(onPlay: (c) => c.repeat()).shimmer(
                        duration: 1200.ms,
                        delay: 400.ms,
                        color: Colors.grey.shade50),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
