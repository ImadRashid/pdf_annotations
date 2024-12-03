import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

class CustomButton extends StatelessWidget {
  final String svgAsset;
  final void Function()? onTap;
  bool isActive = false;
  double? width;
  double? height;
  Widget? customIcon;
  CustomButton(
      {super.key,
      required this.svgAsset,
      required this.onTap,
      required this.isActive,
      this.height,
      this.width,
      this.customIcon});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: !isActive ? Colors.transparent : const Color(0xFFFEE9AC),
          borderRadius: const BorderRadius.all(
            Radius.circular(
              16,
            ),
          ),
        ),
        padding: const EdgeInsets.only(
          top: 10,
          bottom: 10,
          left: 16,
          right: 16,
        ),
        child: customIcon ??
            SvgPicture.asset(
              svgAsset,
              width: width ?? 19,
              height: height ?? 15,
            ),
      ),
    );
  }
}
