Shader "Demonixis/FastPostProcessing"
{
	Properties
	{
		_MainTex("Base (RGB)", 2D) = "white" {}
		_BloomTex("Bloom (RGB)", 2D) = "black" {}
	}

	CGINCLUDE
	#include "UnityCG.cginc"
	#define oneSix     0.1666666
	#define oneThree   0.3333333
    #pragma multi_compile __ BLOOM 
	#pragma multi_compile __ TONEMAPPER_ACES
	#pragma multi_compile __ TONEMAPPER_PHOTOGRAPHIC
	#pragma multi_compile __ TONEMAPPER_HABLE
	#pragma multi_compile __ TONEMAPPER_DAWSON
    #pragma multi_compile __ TONEMAPPER_REINHART
	#pragma multi_compile __ DITHERING
	#pragma multi_compile __ USERLUT_TEXTURE
    #pragma multi_compile __ GAMMA_CORRECTION
    #pragma multi_compile __ ONEPASS_BLOOM 
	uniform sampler2D _MainTex;
	uniform half4 _MainTex_TexelSize;
	uniform	half4 _MainTex_ST;
	uniform float _ThresholdParams;
	uniform half  _Spread;
	uniform sampler2D _BloomTex;
	uniform half _BloomIntensity;
	uniform float _Exposure;
	sampler2D _UserLutTex;
	uniform half4 _UserLutParams;

	struct v2fCombineBloom
	{
		float4 pos : SV_POSITION;
		half2  uv  : TEXCOORD0;
#if ONEPASS_BLOOM
		half4  uv12 : TEXCOORD2;
		half4  uv34 : TEXCOORD3;
#endif
#if UNITY_UV_STARTS_AT_TOP
		half2  uv2 : TEXCOORD4;
#endif
	};

	struct v2fBlurDown
	{
		float4 pos  : SV_POSITION;
		half2  uv0  : TEXCOORD0;
		half4  uv12 : TEXCOORD1;
		half4  uv34 : TEXCOORD2;
	};

	struct v2fBlurUp
	{
		float4 pos  : SV_POSITION;
		half4  uv12 : TEXCOORD0;
		half4  uv34 : TEXCOORD1;
		half4  uv56 : TEXCOORD2;
		half4  uv78 : TEXCOORD3;
	};

	v2fBlurDown vertBlurDown(appdata_img v)
	{
		v2fBlurDown o;
		o.pos = UnityObjectToClipPos(v.vertex);
		o.uv0 = UnityStereoScreenSpaceUVAdjust(v.texcoord.xy, _MainTex_ST);
		o.uv12.xy = UnityStereoScreenSpaceUVAdjust(v.texcoord.xy + half2(1.0h, 1.0h) * _MainTex_TexelSize.xy * _Spread, _MainTex_ST);
		o.uv12.zw = UnityStereoScreenSpaceUVAdjust(v.texcoord.xy + half2(-1.0h, 1.0h) * _MainTex_TexelSize.xy * _Spread, _MainTex_ST);
		o.uv34.xy = UnityStereoScreenSpaceUVAdjust(v.texcoord.xy + half2(-1.0h, -1.0h) * _MainTex_TexelSize.xy * _Spread, _MainTex_ST);
		o.uv34.zw = UnityStereoScreenSpaceUVAdjust(v.texcoord.xy + half2(1.0h, -1.0h) * _MainTex_TexelSize.xy * _Spread, _MainTex_ST);
		return o;
	}

	v2fBlurUp vertBlurUp(appdata_img v)
	{
		v2fBlurUp o;
		o.pos = UnityObjectToClipPos(v.vertex);
		o.uv12.xy = UnityStereoScreenSpaceUVAdjust(v.texcoord.xy + half2(1.0h, 1.0h) * _MainTex_TexelSize.xy * _Spread, _MainTex_ST);
		o.uv12.zw = UnityStereoScreenSpaceUVAdjust(v.texcoord.xy + half2(-1.0h, 1.0h) * _MainTex_TexelSize.xy * _Spread, _MainTex_ST);
		o.uv34.xy = UnityStereoScreenSpaceUVAdjust(v.texcoord.xy + half2(-1.0h, -1.0h) * _MainTex_TexelSize.xy * _Spread, _MainTex_ST);
		o.uv34.zw = UnityStereoScreenSpaceUVAdjust(v.texcoord.xy + half2(1.0h, -1.0h) * _MainTex_TexelSize.xy * _Spread, _MainTex_ST);
		o.uv56.xy = UnityStereoScreenSpaceUVAdjust(v.texcoord.xy + half2(0.0h, 2.0h) * _MainTex_TexelSize.xy * _Spread, _MainTex_ST);
		o.uv56.zw = UnityStereoScreenSpaceUVAdjust(v.texcoord.xy + half2(0.0h, -2.0h) * _MainTex_TexelSize.xy * _Spread, _MainTex_ST);
		o.uv78.xy = UnityStereoScreenSpaceUVAdjust(v.texcoord.xy + half2(2.0h, 0.0h) * _MainTex_TexelSize.xy * _Spread, _MainTex_ST);
		o.uv78.zw = UnityStereoScreenSpaceUVAdjust(v.texcoord.xy + half2(-2.0h, 0.0h) * _MainTex_TexelSize.xy * _Spread, _MainTex_ST);
		return o;
	}

	v2fCombineBloom vertCombineBloom(appdata_img v)
	{
		v2fCombineBloom o;

		o.pos = UnityObjectToClipPos(v.vertex);
		o.uv = UnityStereoScreenSpaceUVAdjust(v.texcoord, _MainTex_ST);

#if UNITY_UV_STARTS_AT_TOP
		o.uv2 = o.uv;
		if (_MainTex_TexelSize.y < 0.0)
			o.uv.y = 1.0 - o.uv.y;
#endif

#if ONEPASS_BLOOM
		o.uv12.xy = UnityStereoScreenSpaceUVAdjust(v.texcoord.xy + half2(1.0h, 1.0h) * _MainTex_TexelSize.xy * _Spread, _MainTex_ST);
		o.uv12.zw = UnityStereoScreenSpaceUVAdjust(v.texcoord.xy + half2(-1.0h, 1.0h) * _MainTex_TexelSize.xy * _Spread, _MainTex_ST);
		o.uv34.xy = UnityStereoScreenSpaceUVAdjust(v.texcoord.xy + half2(-1.0h, -1.0h) * _MainTex_TexelSize.xy * _Spread, _MainTex_ST);
		o.uv34.zw = UnityStereoScreenSpaceUVAdjust(v.texcoord.xy + half2(1.0h, -1.0h) * _MainTex_TexelSize.xy * _Spread, _MainTex_ST);
#endif

		return o;
	}

	fixed4 fragBlurDownFirstPass(v2fBlurDown i) : SV_Target
	{
		fixed4 col0 = tex2D(_MainTex, i.uv0);
		fixed4 col1 = tex2D(_MainTex, i.uv12.xy);
		fixed4 col2 = tex2D(_MainTex, i.uv12.zw);
		fixed4 col3 = tex2D(_MainTex, i.uv34.xy);
		fixed4 col4 = tex2D(_MainTex, i.uv34.zw);

		fixed4 col = col0 + col1 * 0.25 + col2 * 0.25 + col3 * 0.25 + col4 * 0.25;
		col = col * 0.5;
		col = col + _ThresholdParams;

		col = max(col, 0.0);
		return col;
	}

	fixed4 fragBlurDown(v2fBlurDown i) : SV_Target
	{
		fixed4 col0 = tex2D(_MainTex, i.uv0);
		fixed4 col1 = tex2D(_MainTex, i.uv12.xy);
		fixed4 col2 = tex2D(_MainTex, i.uv12.zw);
		fixed4 col3 = tex2D(_MainTex, i.uv34.xy);
		fixed4 col4 = tex2D(_MainTex, i.uv34.zw);

		fixed4 col = col0 + col1 * 0.25 + col2 * 0.25 + col3 * 0.25 + col4 * 0.25;
		col = col * 0.5;
		return col;
	}

	fixed4 fragBlurUp(v2fBlurUp i) : SV_Target
	{
		fixed4 col1 = tex2D(_MainTex, i.uv12.xy);
		fixed4 col2 = tex2D(_MainTex, i.uv12.zw);
		fixed4 col3 = tex2D(_MainTex, i.uv34.xy);
		fixed4 col4 = tex2D(_MainTex, i.uv34.zw);
		fixed4 col5 = tex2D(_MainTex, i.uv56.xy);
		fixed4 col6 = tex2D(_MainTex, i.uv56.zw);
		fixed4 col7 = tex2D(_MainTex, i.uv78.xy);
		fixed4 col8 = tex2D(_MainTex, i.uv78.zw);

		return col1 * oneThree + col2 * oneThree + col3 * oneThree + col4 * oneThree + col5 * oneSix + col6 * oneSix + col7 * oneSix + col8 * oneSix;
	}

#if TONEMAPPER_ACES
	half3 tonemapACES(half3 color)
	{
		color *= _Exposure;
		
		const half3 a = 2.51f;
		const half3 b = 0.03f;
		const half3 c = 2.43f;
		const half3 d = 0.59f;
		const half3 e = 0.14f;
		return saturate((color * (a * color + b)) / (color * (c * color + d) + e));
	}
#endif

#if TONEMAPPER_PHOTOGRAPHIC
	half3 tonemapPhotographic(half3 color)
	{
		color *= _Exposure;
		return 1.0 - exp2(-color);
	}
#endif

#if TONEMAPPER_HABLE
	half3 tonemapHable(half3 color)
	{
		const half a = 0.15;
		const half b = 0.50;
		const half c = 0.10;
		const half d = 0.20;
		const half e = 0.02;
		const half f = 0.30;
		const half w = 11.2;

		color *= _Exposure * 2.0;
		half3 curr = ((color * (a * color + c * b) + d * e) / (color * (a * color + b) + d * f)) - e / f;
		color = w;
		half3 whiteScale = 1.0 / (((color * (a * color + c * b) + d * e) / (color * (a * color + b) + d * f)) - e / f);
		return curr * whiteScale;
	}

#endif

#if TONEMAPPER_DAWSON
	half3 tonemapHejlDawson(half3 color)
	{
		const half a = 6.2;
		const half b = 0.5;
		const half c = 1.7;
		const half d = 0.06;

		color *= _Exposure;
		color = max((0.0).xxx, color - (0.004).xxx);
		color = (color * (a * color + b)) / (color * (a * color + c) + d);
		return color * color;
	}
#endif

#if TONEMAPPER_REINHART
	half3 tonemapReinhard(half3 color)
	{
		half lum = Luminance(color);
		half lumTm = lum * _Exposure;
		half scale = lumTm / (1.0 + lumTm);
		return color * scale / lum;
	}
#endif

#if USERLUT_TEXTURE
	half3 apply_lut(sampler2D tex, half3 uvw, half3 scaleOffset)
	{
		uvw.z *= scaleOffset.z;
		half shift = floor(uvw.z);
		uvw.xy = uvw.xy * scaleOffset.z * scaleOffset.xy + scaleOffset.xy * 0.5;
		uvw.x += shift * scaleOffset.y;
		uvw.xyz = lerp(tex2D(tex, uvw.xy).rgb, tex2D(tex, uvw.xy + half2(scaleOffset.y, 0)).rgb, uvw.z - shift);
		return uvw;
	}
#endif

	half4 fragCombineBloom(v2fCombineBloom i) : SV_Target
	{
		half2 uv = i.uv;
#if UNITY_UV_STARTS_AT_TOP
		uv = i.uv2;
#endif
		half3 col = tex2D(_MainTex, uv).rgb;

#if BLOOM
		col += tex2D(_BloomTex, uv).rgb * _BloomIntensity;
#elif ONEPASS_BLOOM
		fixed4 col0 = tex2D(_MainTex, uv);
		fixed4 col1 = tex2D(_MainTex, i.uv12.xy);
		fixed4 col2 = tex2D(_MainTex, i.uv12.zw);
		fixed4 col3 = tex2D(_MainTex, i.uv34.xy);
		fixed4 col4 = tex2D(_MainTex, i.uv34.zw);

		fixed4 fcol = col0 + col1 * 0.25 + col2 * 0.25 + col3 * 0.25 + col4 * 0.25;
		fcol = fcol * 0.5;
		fcol = fcol + _ThresholdParams;
		fcol = max(fcol, 0.0);
		col += fcol * _BloomIntensity;
		//col = fcol;
#endif

#if TONEMAPPER_ACES
		col = tonemapACES(col);
#elif TONEMAPPER_PHOTOGRAPHIC
		col = tonemapPhotographic(col);
#elif TONEMAPPER_HABLE
		col = tonemapHable(col);
#elif TONEMAPPER_DAWSON
		col = tonemapHejlDawson(col);
#elif TONEMAPPER_REINHART
		col = tonemapReinhard(col);
#endif

#if GAMMA_CORRECTION
		col = pow(col, 0.454545);
#endif

#if DITHERING
		// Interleaved Gradient Noise from http://www.iryoku.com/next-generation-post-processing-in-call-of-duty-advanced-warfare (slide 122)
		half3 magic = float3(0.06711056, 0.00583715, 52.9829189);
		half gradient = frac(magic.z * frac(dot(uv / _MainTex_TexelSize, magic.xy))) / 255.0;
		col.rgb -= gradient.xxx;
#endif

#if USERLUT_TEXTURE
		half3 lc = apply_lut(_UserLutTex, saturate(col.rgb), _UserLutParams.xyz);
		col = lerp(col, lc, _UserLutParams.w);
#endif

		return half4(col, 1.0);
	}

	ENDCG
	SubShader
	{
		Cull Off ZWrite Off ZTest Always

		//initial downscale and threshold
		Pass
		{
CGPROGRAM
#pragma vertex vertBlurDown
#pragma fragment fragBlurDownFirstPass
ENDCG
		}

		//down pass
		Pass
		{
CGPROGRAM
#pragma vertex vertBlurDown
#pragma fragment fragBlurDown
ENDCG
		}

		//up pass
		Pass
		{
CGPROGRAM
#pragma vertex vertBlurUp
#pragma fragment fragBlurUp
ENDCG
		}

		//final bloom
		Pass
		{
CGPROGRAM
#pragma vertex vertCombineBloom
#pragma fragment fragCombineBloom
ENDCG
		}
	}
}