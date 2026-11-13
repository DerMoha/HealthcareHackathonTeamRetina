"""Pydantic schemas. Field names follow docs/api-contract.md exactly."""
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class Patient(BaseModel):
    name: str
    age: int
    appearance: str
    personality: str


class Zone(BaseModel):
    id: str
    label: str
    attach_to: str
    offset: list[float]
    radius: float


class DialogueLine(BaseModel):
    id: str
    learner: str
    patient: str


class InvestigationInfo(BaseModel):
    id: str
    label: str


class MeasurementInfo(BaseModel):
    id: str
    label: str
    kind: Literal["circumference", "length"]


class OrthosisSize(BaseModel):
    id: str
    label: str
    wrist_cm: list[float]  # [min, max] printed on the tray


class Orthotics(BaseModel):
    measurements: list[MeasurementInfo] = []
    sizes: list[OrthosisSize] = []
    tightness: list[str] = []


class CaseCatalog(BaseModel):
    """Dashboard metadata. Spoiler-free: never names the diagnosis."""
    summary: str = ""
    icon: str | None = None          # SF Symbol name
    setting: str | None = None
    skills: list[str] = []
    allowed_moods: list[str] = ["calm"]
    allowed_avatars: list[str] = ["male"]
    default_mood: str = "calm"
    default_avatar: str = "male"
    avatar_model: str | None = None  # bundled model name that overrides the avatar choice


class UltrasoundRegion(BaseModel):
    """A scan area on the patient's belly. Which views it yields stays with the engine."""
    id: str
    label: str
    attach_to: str   # anchor name in the avatar's sidecar (abdomen_fundus, ...)
    radius: float


class UltrasoundInfo(BaseModel):
    regions: list[UltrasoundRegion]


class SessionConfig(BaseModel):
    """What the patient is like in this encounter. Never changes findings or scoring."""
    mood: str
    avatar: str


class SessionConfigRequest(BaseModel):
    mood: str | None = None      # default: the case's default_mood
    avatar: str | None = None    # default: the case's default_avatar


class CasePublic(BaseModel):
    case_id: str
    title: str
    learner_brief: str
    patient: Patient
    voice_context: str
    zones: list[Zone]
    scripted_dialogue: list[DialogueLine]
    investigations: list[InvestigationInfo] = []
    orthotics: Orthotics = Orthotics()
    catalog: CaseCatalog | None = None
    ultrasound: UltrasoundInfo | None = None  # only cases with a probe and a machine


class Health(BaseModel):
    status: str
    version: str
    cases: int


class SessionCreate(BaseModel):
    case_id: str
    config: SessionConfigRequest | None = None
    scenario_code: str | None = None  # launch code of a published MedSim Studio scenario


class SessionInfo(BaseModel):
    session_id: str
    started_at: str
    case: CasePublic
    config: SessionConfig | None = None
    scenario: dict | None = None  # studio.ScenarioRuntime when launched from a published scenario


class ExamineRequest(BaseModel):
    body_part: str
    action: str = "palpation"


class ExamineResult(BaseModel):
    body_part: str
    action: str
    finding: str
    pain_level: int = Field(ge=0, le=10)
    reaction: Literal["strong_pain", "mild_pain", "no_pain"]
    patient_response: str
    animation: Literal["arm_withdrawal", "flinch", "none"]
    voice_context: str
    repeat_count: int


class InvestigationRequest(BaseModel):
    investigation_id: str


class InvestigationResult(BaseModel):
    investigation_id: str
    label: str
    modality: str
    title: str
    report: str
    impression: str
    image: str | None  # bundled image name in the app, or null: report only
    image_credit: str
    ordered_at: str
    repeat_count: int


class MeasurementRequest(BaseModel):
    measurement_id: str
    value_cm: float | None = None  # measured on the avatar; ignored when the case predefines it


class MeasurementResult(BaseModel):
    measurement_id: str
    label: str
    kind: str
    value_cm: float
    source: Literal["case", "avatar"]


class OrthosisFit(BaseModel):
    size: str
    orientation: Literal["thumb_radial", "thumb_ulnar"]
    offset_cm: float  # centre of the support, from the wrist joint towards the elbow
    tightness: str


class FitRequest(BaseModel):
    fit: OrthosisFit | None = None  # null or absent = support removed


class FitAck(BaseModel):
    attempt: int
    voice_note: str  # context for the voice agent; never spoken, never an outcome label
    # What the patient says unprompted when the fit is uncomfortable (the app debounces it).
    comfortable: bool
    patient_response: str
    voice_context: str
    animation: Literal["arm_withdrawal", "flinch", "none"]


class FittingCheckRequest(BaseModel):
    check: Literal["comfort", "neurovascular"]


class FittingCheckResult(BaseModel):
    check: str
    phase: Literal["before", "after"]
    finding: str | None  # neurovascular only
    patient_response: str
    voice_context: str
    comfortable: bool
    animation: Literal["arm_withdrawal", "flinch", "none"]


class GelResult(BaseModel):
    applied: bool
    patient_response: str
    voice_context: str
    repeat_count: int


class ScanRequest(BaseModel):
    region_id: str
    # What the scene shows (gel on the skin). The engine's own record of gel events decides;
    # an explicit false can only make the scan worse, never better.
    gel_applied: bool | None = None


class ScanMeasurement(BaseModel):
    label: str
    value: float
    unit: str


class ScanResult(BaseModel):
    region_id: str
    view_id: str | None        # null: no usable image
    image: str | None          # id in ultrasound_manifest.json, or null
    title: str
    caption: str
    measurements: list[ScanMeasurement]
    image_credit: str
    depth_cm: float            # display decoration of the simulated machine
    gain: int
    quality: Literal["good", "poor"]
    gel_applied: bool
    patient_response: str      # may be empty: the patient says nothing
    voice_context: str
    repeat_count: int


class InteractionRequest(BaseModel):
    role: Literal["learner", "patient"]
    text: str
    timestamp: datetime | None = None


class InteractionCount(BaseModel):
    count: int


class Notes(BaseModel):
    """The learner's notebook. Compared with the session record; never a source of points."""
    history: str = ""
    examination: str = ""
    assessment: str = ""
    interpretation: str = ""  # what the investigation results mean
    management: str = ""      # immediate management
    follow_up: str = ""       # further imaging / follow-up plan


class DiagnoseRequest(BaseModel):
    diagnosis: str = Field(min_length=1)
    notes: Notes | None = None


class DocumentationItem(BaseModel):
    criterion_id: str
    label: str
    status: Literal["documented", "undocumented", "unsupported"]
    comment: str


class DiagnosticAssessment(BaseModel):
    verdict: Literal["correct", "partial", "incorrect", "not_submitted"]
    explanation: str
    expected: str | None


class CriterionResult(BaseModel):
    id: str
    label: str
    met: bool
    points: int
    max_points: int
    method: Literal["keyword", "rule"]
    evidence: str | None
    comment: str
    area: str | None = None  # management / fitting criteria only, e.g. investigation | interpretation | management | safety | measurement | fitting


class CategoryResult(BaseModel):
    id: str
    title: str
    score: int
    max_score: int
    criteria: list[CriterionResult]


class ManagementAssessment(BaseModel):
    """Investigation and management: scored separately, not part of total_score."""
    title: str
    score: int
    max_score: int
    criteria: list[CriterionResult]


class FittingAssessment(BaseModel):
    """Measurement and orthosis fitting: scored separately, not part of total_score."""
    title: str
    score: int
    max_score: int
    criteria: list[CriterionResult]
    final_fit: OrthosisFit | None
    reference: dict | None      # size, orientation, offset_cm [min, max], tightness; null before a diagnosis
    explanation: str | None     # why the final fit was or was not appropriate; null before a diagnosis


class ReplayZone(BaseModel):
    """Teaching content for Spatial Clinical Replay; only sent after a diagnosis."""
    zone_id: str
    label: str
    important: bool
    examined: bool
    finding: str | None      # only when examined
    pain_level: int | None
    explanation: str         # what examining it contributed, or what was missed


class ScanReviewItem(BaseModel):
    """One expected (or optional) ultrasound view versus what the learner obtained. Only after a diagnosis."""
    id: str
    label: str
    expected: bool
    obtained: bool
    view_id: str | None      # the view that counted, if obtained
    image: str | None        # manifest id: the learner's own view, or an example when missed
    explanation: str


class Feedback(BaseModel):
    session_id: str
    case_id: str
    diagnosis_submitted: str | None
    total_score: int
    max_score: int
    summary: str
    transcript_available: bool
    diagnostic_assessment: DiagnosticAssessment
    categories: list[CategoryResult]
    strengths: list[str]
    missed: list[str]
    relevant_findings: list[str]
    next_steps: list[str]
    documentation: list[DocumentationItem]
    management: ManagementAssessment
    investigations: list[str]
    fitting: FittingAssessment
    replay: list[ReplayZone]
    scan_review: list[ScanReviewItem] = []
    disclaimer: str


class TokenResponse(BaseModel):
    token: str


class ConversationSummary(BaseModel):
    """ElevenLabs' post-call summary of one voice conversation. A draft for the learner, never scored."""
    status: Literal["pending", "done", "failed"]
    summary: str | None = None


class TranscriptionResponse(BaseModel):
    text: str
