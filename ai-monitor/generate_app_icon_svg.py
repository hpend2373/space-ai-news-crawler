#!/usr/bin/env python3
"""
Brief 앱 아이콘 SVG 생성기
"O" 모양의 원형 디자인
"""

import os

# SVG 템플릿
SVG_TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <!-- 배경 그라디언트 -->
    <linearGradient id="bgGradient" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#1A1A33;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#0D0D26;stop-opacity:1" />
    </linearGradient>
    
    <!-- 메인 링 그라디언트 -->
    <linearGradient id="ringGradient" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#5CB6FF;stop-opacity:1" />
      <stop offset="50%" style="stop-color:#9466F2;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#F2668E;stop-opacity:1" />
    </linearGradient>
    
    <!-- 광택 효과 -->
    <radialGradient id="shineGradient" cx="30%" cy="30%">
      <stop offset="0%" style="stop-color:#FFFFFF;stop-opacity:0.3" />
      <stop offset="100%" style="stop-color:#FFFFFF;stop-opacity:0" />
    </radialGradient>
    
    <!-- 중앙 강조 -->
    <radialGradient id="centerGlow" cx="50%" cy="50%">
      <stop offset="0%" style="stop-color:#5CF2C6;stop-opacity:0.6" />
      <stop offset="100%" style="stop-color:#5CF2C6;stop-opacity:0" />
    </radialGradient>
  </defs>
  
  <!-- 배경 -->
  <rect width="1024" height="1024" fill="url(#bgGradient)" rx="226" />
  
  <!-- 메인 "O" 링 -->
  <circle cx="512" cy="512" r="359" fill="url(#ringGradient)" />
  
  <!-- 내부 투명 원 -->
  <circle cx="512" cy="512" r="230" fill="url(#bgGradient)" opacity="0.95" />
  
  <!-- 광택 효과 -->
  <circle cx="512" cy="512" r="359" fill="url(#shineGradient)" />
  
  <!-- 중앙 글로우 -->
  <circle cx="512" cy="512" r="128" fill="url(#centerGlow)" filter="blur(4px)" />
  
  <!-- 반짝이 (왼쪽 상단) -->
  <circle cx="256" cy="276" r="13" fill="white" opacity="0.8" filter="blur(1px)" />
  
  <!-- 반짝이 (오른쪽 상단) -->
  <circle cx="774" cy="328" r="13" fill="white" opacity="0.8" filter="blur(1px)" />
  
  <!-- 반짝이 (하단) -->
  <circle cx="666" cy="778" r="13" fill="white" opacity="0.8" filter="blur(1px)" />
</svg>
"""

# 미니멀 버전
SVG_MINIMAL_TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <!-- 배경 -->
    <rect id="bg" width="1024" height="1024" fill="#14142E" rx="226" />
    
    <!-- 링 그라디언트 -->
    <linearGradient id="ringGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#5CB6FF" />
      <stop offset="50%" style="stop-color:#9466F2" />
      <stop offset="100%" style="stop-color:#F2668E" />
    </linearGradient>
    
    <!-- 광택 -->
    <linearGradient id="shine" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" style="stop-color:#FFFFFF;stop-opacity:0.4" />
      <stop offset="100%" style="stop-color:#FFFFFF;stop-opacity:0" />
    </linearGradient>
  </defs>
  
  <!-- 배경 -->
  <use href="#bg" />
  
  <!-- 메인 링 (stroke) -->
  <circle cx="512" cy="512" r="318" 
          fill="none" 
          stroke="url(#ringGrad)" 
          stroke-width="123" />
  
  <!-- 광택 효과 -->
  <circle cx="512" cy="512" r="318" 
          fill="none" 
          stroke="url(#shine)" 
          stroke-width="41" 
          transform="rotate(-45 512 512)" />
</svg>
"""

def save_svg(filename: str, content: str):
    """SVG 파일 저장"""
    with open(filename, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"✅ 생성: {filename}")

def main():
    print("🎨 Brief 앱 아이콘 SVG 생성")
    print("")
    
    # SVG 파일 생성
    save_svg("AppIcon_Full.svg", SVG_TEMPLATE)
    save_svg("AppIcon_Minimal.svg", SVG_MINIMAL_TEMPLATE)
    
    print("")
    print("다음 단계:")
    print("1. SVG를 Figma/Illustrator/Sketch에서 열기")
    print("2. 1024x1024로 PNG 내보내기")
    print("3. 또는 다음 명령으로 변환:")
    print("")
    print("   # ImageMagick 사용")
    print("   magick AppIcon_Full.svg -resize 1024x1024 AppIcon_1024.png")
    print("")
    print("   # Inkscape 사용")
    print("   inkscape AppIcon_Full.svg --export-filename=AppIcon_1024.png --export-width=1024")
    print("")
    print("4. Xcode Assets.xcassets/AppIcon.appiconset에 추가")

if __name__ == "__main__":
    main()
