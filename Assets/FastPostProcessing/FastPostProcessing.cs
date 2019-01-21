using UnityEngine;

namespace Demonixis.Toolbox
{
    using UnityGraphics = UnityEngine.Graphics;

    [ExecuteAlways]
    [RequireComponent(typeof(Camera))]
    [AddComponentMenu("Demonixis/FastPostProcessing")]
    public sealed class FastPostProcessing : MonoBehaviour
    {
        public enum Bloom
        {
            None = 0, OnePass, MultiPass
        }

        public enum ToneMapper
        {
            None = 0, ACES, Dawson, Hable, Photographic, Reinhart
        }

        private Material m_PostProcessMaterial = null;
        private Vector4 m_UserLutParams;
        private bool m_UserLutEnabled = true;

        [Header("Material")]
        [SerializeField]
        private Shader m_Shader = null;

        [Header("Bloom")]
        [SerializeField]
        private Bloom m_Bloom = Bloom.MultiPass;
        [Range(0.0f, 1.5f)]
        [SerializeField]
        private float m_Threshold = 0.9f;
        [Range(0.00f, 100.0f)]
        [SerializeField]
        private float m_Intensity = 15.0f;
        [Range(0.0f, 5.5f)]
        [SerializeField]
        private float m_BlurSize = 0.0f;
        [Range(0, 8)]
        [SerializeField]
        private int m_BlurIterations = 2;
        [SerializeField]
        private bool m_DownscalePass = true;
        [SerializeField]
        private bool m_UpscalePass = true;

        [Header("ToneMapper")]
        [SerializeField]
        private ToneMapper m_ToneMapper = ToneMapper.ACES;
        [SerializeField]
        private float m_Exposure = 1.0f;
        [SerializeField]
        private Texture2D m_UserLutTexture = null;
        [Range(0.0f, 1.0f)]
        [SerializeField]
        private float m_LutContribution = 0.5f;
        [SerializeField]
        private bool m_Dithering = false;

        [Header("Gamma Correction")]
        [SerializeField]
        private bool m_GammaCorrectionEnabled = false;

        #region Properties

        public Bloom BloomType
        {
            get => m_Bloom;
            set
            {
                m_Bloom = value;
                SetDefine("BLOOM", m_Bloom == Bloom.MultiPass);
                SetDefine("ONEPASS_BLOOM", m_Bloom == Bloom.OnePass);
            }
        }

        public ToneMapper Tonemapper
        {
            get => m_ToneMapper;
            set
            {
                m_ToneMapper = value;
                UpdateTonemapperDefines();
            }
        }

        public Texture2D UserLUTTexture
        {
            get => m_UserLutTexture;
            set
            {
                m_UserLutTexture = value;
                m_UserLutEnabled = m_UserLutTexture != null;

                if (m_UserLutEnabled)
                    m_UserLutParams = new Vector4(1f / m_UserLutTexture.width, 1f / m_UserLutTexture.height, m_UserLutTexture.height - 1f, m_LutContribution);

                SetDefine("USERLUT_TEXTURE", m_UserLutEnabled);
            }
        }

        public bool Dithering
        {
            get => m_Dithering;
            set
            {
                m_Dithering = value;
                SetDefine("DITHERING", m_Dithering);
            }
        }

        public bool GammaCorrection
        {
            get => m_GammaCorrectionEnabled;
            set
            {
                m_GammaCorrectionEnabled = value;
                SetDefine("GAMMA_CORRECTION", m_GammaCorrectionEnabled);
            }
        }

        public float UserLUTContribution
        {
            get => m_UserLutParams.z;
            set => m_UserLutParams.z = value;
        }

        public Material Material
        {
            get => m_PostProcessMaterial;
            set
            {
                m_PostProcessMaterial = value;
                OnEnable();
            }
        }

        public Shader Shader
        {
            get => m_Shader;
            set
            {
                if (value == null)
                {
                    Debug.Log("Trying to put a null shader.");
                    return;
                }

                m_Shader = value;
                m_PostProcessMaterial = new Material(value);
            }
        }

        #endregion

        private void OnEnable()
        {
            if (m_Shader == null)
                m_Shader = Shader.Find("Demonixis/FastPostProcessing");

            if (m_PostProcessMaterial == null)
                m_PostProcessMaterial = new Material(m_Shader);

            m_UserLutEnabled = m_UserLutTexture != null;

            if (m_UserLutEnabled)
                m_UserLutParams = new Vector4(1.0f / m_UserLutTexture.width, 1.0f / m_UserLutTexture.height, m_UserLutTexture.height - 1.0f, m_LutContribution);

            SetDefine("BLOOM", m_Bloom == Bloom.MultiPass);
            SetDefine("ONEPASS_BLOOM", m_Bloom == Bloom.OnePass);
            SetDefine("DITHERING", m_Dithering);
            SetDefine("USERLUT_TEXTURE", m_UserLutEnabled && m_UserLutTexture != null);
            SetDefine("GAMMA_CORRECTION", m_GammaCorrectionEnabled);

            UpdateTonemapperDefines();
        }

        private void UpdateTonemapperDefines()
        {
            SetDefine("TONEMAPPER_ACES", m_ToneMapper == ToneMapper.ACES);
            SetDefine("TONEMAPPER_HABLE", m_ToneMapper == ToneMapper.Hable);
            SetDefine("TONEMAPPER_PHOTOGRAPHIC", m_ToneMapper == ToneMapper.Photographic);
            SetDefine("TONEMAPPER_DAWSON", m_ToneMapper == ToneMapper.Dawson);
            SetDefine("TONEMAPPER_REINHART", m_ToneMapper == ToneMapper.Reinhart);
        }

        private void SetDefine(string define, bool isEnabled)
        {
            if (m_PostProcessMaterial == null)
            {
                Debug.LogWarning("Post Process Material is null");
                return;
            }

            if (isEnabled)
                m_PostProcessMaterial.EnableKeyword(define);
            else
                m_PostProcessMaterial.DisableKeyword(define);
        }

#if UNITY_EDITOR
        private void OnValidate() => OnEnable();
#endif

        private void OnRenderImage(RenderTexture source, RenderTexture destination)
        {
            if (m_PostProcessMaterial == null || m_PostProcessMaterial?.shader == null)
            {
                Debug.LogWarning("Material Or Shader NULL");
                UnityGraphics.Blit(source, destination);
                return;
            }

            RenderTexture rt = null;

            if (m_Bloom == Bloom.MultiPass)
            {
                var rtW = source.width / 4;
                var rtH = source.height / 4;
                rt = RenderTexture.GetTemporary(rtW, rtH, 0, source.format);
                rt.DiscardContents();

                //initial downsample
                m_PostProcessMaterial.SetFloat("_Spread", m_BlurSize);
                m_PostProcessMaterial.SetFloat("_ThresholdParams", -m_Threshold);
                UnityGraphics.Blit(source, rt, m_PostProcessMaterial, 0);

                if (m_DownscalePass)
                {
                    for (int i = 0; i < m_BlurIterations - 1; i++)
                    {
                        var rt2 = RenderTexture.GetTemporary(rt.width / 2, rt.height / 2, 0, source.format);
                        rt2.DiscardContents();

                        m_PostProcessMaterial.SetFloat("_Spread", m_BlurSize);
                        UnityGraphics.Blit(rt, rt2, m_PostProcessMaterial, 1);
                        RenderTexture.ReleaseTemporary(rt);
                        rt = rt2;
                    }
                }

                if (m_UpscalePass)
                {
                    for (var i = 0; i < m_BlurIterations - 1; i++)
                    {
                        var rt2 = RenderTexture.GetTemporary(rt.width * 2, rt.height * 2, 0, source.format);
                        rt2.DiscardContents();

                        m_PostProcessMaterial.SetFloat("_Spread", m_BlurSize);
                        UnityGraphics.Blit(rt, rt2, m_PostProcessMaterial, 2);
                        RenderTexture.ReleaseTemporary(rt);
                        rt = rt2;
                    }
                }
            }

            // Final pass
            if (m_Bloom == Bloom.OnePass)
            {
                m_PostProcessMaterial.SetFloat("_ThresholdParams", -m_Threshold);
                m_PostProcessMaterial.SetFloat("_Spread", m_BlurSize);
                m_PostProcessMaterial.SetFloat("_BloomIntensity", m_Intensity);
            }

            if (m_ToneMapper != ToneMapper.None)
                m_PostProcessMaterial.SetFloat("_Exposure", m_Exposure);

            if (m_UserLutEnabled)
            {
                m_PostProcessMaterial.SetVector("_UserLutParams", m_UserLutParams);
                m_PostProcessMaterial.SetTexture("_UserLutTex", m_UserLutTexture);
            }

            if (m_Bloom == Bloom.MultiPass)
            {
                m_PostProcessMaterial.SetFloat("_BloomIntensity", m_Intensity);
                m_PostProcessMaterial.SetTexture("_BloomTex", rt);
            }

            UnityGraphics.Blit(source, destination, m_PostProcessMaterial, 3);

            if (m_Bloom == Bloom.MultiPass)
                RenderTexture.ReleaseTemporary(rt);
        }
    }
}