# Built-in regulatory compliance initiatives this platform may assign, by short key.
#
# Every ID below was checked on 2026-11-17 against the initiative's JSON in Microsoft's own repository
# (github.com/Azure/azure-policy, built-in-policies/policySetDefinitions/), and its name against the
# Defender for Cloud list of standards for Azure. `file` is the path in that repository, so anyone can
# re-check an ID or see which policies a standard contains. Built-in versions change without notice;
# the IDs don't.
#
# `status` says how far to trust the score:
#   ga         - a full built-in standard, shown in Defender for Cloud's regulatory compliance dashboard
#   preview    - Defender for Cloud marks the standard as preview
#   thin       - built in, but only a handful of automated checks; most of the standard is process
#   superseded - still built in, but the framework itself has been retired or replaced

locals {
  initiative_prefix = "/providers/Microsoft.Authorization/policySetDefinitions"

  catalog = {
    # ---- Baseline (P&T normally assigns MCSB at their intermediate root; inherited, so not assigned here)
    "mcsb" = {
      guid   = "1f3afdf9-d0c9-4c3d-847f-89da613e70a8"
      name   = "Microsoft cloud security benchmark"
      file   = "Security Center/AzureSecurityCenter.json"
      status = "ga"
    }
    "mcsb-v2" = {
      guid   = "e3ec7e09-768c-4b64-882c-fcada3772047"
      name   = "Microsoft cloud security benchmark v2"
      file   = "Security Center/MCSBv2.json"
      status = "preview" # Defender: "MCSB v2 (preview) is also available"; adds AI coverage
    }

    # ---- Core: what bank and insurer clients ask a vendor for
    "soc2" = {
      guid   = "4054785f-702b-4a98-9215-009cbd58b141"
      name   = "SOC 2 Type 2"
      file   = "Regulatory Compliance/SOC_2.json"
      status = "ga"
    }
    "soc2023" = {
      guid   = "53ad89f5-8542-49e9-ba81-1cbd686e0d52"
      name   = "SOC 2023"
      file   = "Regulatory Compliance/SOC_2023.json"
      status = "ga"
    }
    "iso27001-2022" = {
      guid   = "5e4ff661-23bf-42fa-8e3a-309a55091cc7"
      name   = "ISO/IEC 27001 2022"
      file   = "Regulatory Compliance/ISO_IEC_27001_2022.json"
      status = "ga" # 58 checks, mapped to clauses 6-10 (Defender plans, logging, CMK), not Annex A
    }
    "nist80053r5" = {
      guid   = "179d1daa-458f-4e47-8086-2a68d0d6c38f"
      name   = "NIST SP 800-53 Rev. 5"
      file   = "Regulatory Compliance/NIST_SP_800-53_R5.json"
      status = "ga"
    }
    "nist80053r511" = {
      guid   = "60205a79-6280-4e20-a147-e2011e09dc78"
      name   = "NIST SP 800-53 R5.1.1"
      file   = "Regulatory Compliance/NIST_SP_800-53_R5.1.1.json"
      status = "ga"
    }
    "pci4" = {
      guid   = "a06d5deb-24aa-4991-9d58-fa7563154e31"
      name   = "PCI DSS v4.0.1"
      file   = "Regulatory Compliance/PCI_DSS_v4.0.1.json"
      status = "ga" # only if an app ever touches card data
    }
    "cis-azure3" = {
      guid   = "470a962c-86a0-433b-803a-3c176b5ce79c"
      name   = "CIS Azure Foundations v3.0.0"
      file   = "Regulatory Compliance/CIS_Azure_Foundations_v3.0.0.json"
      status = "ga"
    }

    # ---- US financial clients
    "nist-csf2" = {
      guid   = "184a0e05-7b06-4a68-bbbe-13b8353bc613"
      name   = "NIST CSF v2.0"
      file   = "Regulatory Compliance/NIST_CSF_v2.0.json"
      status = "ga" # what the FFIEC now points banks to instead of the CAT
    }
    "ffiec-cat" = {
      guid   = "1d5dbdd5-6f93-43ce-a939-b19df3753cf7"
      name   = "FFIEC CAT 2017"
      file   = "Regulatory Compliance/FFIEC_CAT_2017.json"
      status = "superseded" # the FFIEC retired the CAT on 2025-08-31 (OCC Bulletin 2024-25)
    }

    # ---- EU and UK clients
    "dora" = {
      guid   = "f9c0485f-da8e-43b5-961e-58ebd54b907c"
      name   = "DORA 2022 2554"
      file   = "Regulatory Compliance/DORA_2022_2554.json"
      status = "ga"
    }
    "nis2" = {
      guid   = "42346945-b531-41d8-9e46-f95057672e88"
      name   = "EU 2022/2555 (NIS2) 2022"
      file   = "Regulatory Compliance/EU_2555_(NIS2)_2022.json"
      status = "ga"
    }
    "gdpr" = {
      guid   = "7326812a-86a4-40c8-af7c-8945de9c4913"
      name   = "EU General Data Protection Regulation (GDPR) 2016/679"
      file   = "Regulatory Compliance/EU_GDPR_2016_679.json"
      status = "ga"
    }
    "uk-official" = {
      guid   = "3937f550-eedd-4639-9c5e-294358be442e"
      name   = "UK OFFICIAL and UK NHS"
      file   = "Regulatory Compliance/ukofficial_audit.json"
      status = "ga"
    }
    "ncsc-caf" = {
      guid   = "6d220abf-cf6f-4b17-8f7e-0644c4cc84b4"
      name   = "NCSC Cyber Assurance Framework (CAF) v3.2"
      file   = "Regulatory Compliance/UK_NCSC_CAF_v3.2.json"
      status = "ga"
    }

    # ---- AI regulation
    "eu-ai-act" = {
      guid   = "1308bccf-446a-4283-a4e0-0c983fe7a572"
      name   = "EU AI Act 2024 1689"
      file   = "Regulatory Compliance/EU_AI_Act_2024_1689.json"
      status = "thin" # 6 checks: AI services logs and Private Link, AI Search network, APIM TLS, Defender for APIs
    }
    "nist-ai-rmf" = {
      guid   = "f58a876c-ec25-417e-9634-58d2a93e3fe2"
      name   = "NIST AI RMF v1.0"
      file   = "Regulatory Compliance/NIST_AI_RMF_v1.0.json"
      status = "thin" # 1 check: diagnostic logs on Azure AI services
    }
  }
}
