import SwiftUI
import AppKit
import SQLite3

struct Patient: Codable, Identifiable, Hashable { var id: String; var name: String; var gender: String; var birthOrAge: String; var medicalNo: String; var phone: String; var address: String; var feeType: String; var diagnosis: String; var allergy: String }
struct VisitRecord: Codable, Identifiable, Hashable { var id: String; var name: String; var gender: String; var age: String; var department: String; var date: String?; var diagnosis: String; var doctor: String; var phone: String; var total: String; var visitKey: String; var allergy: String; var feeType: String; var displayDate: String; var patientKey: String; var prescription: String; var extraPrescription: String; var symptoms: String; var category: String; var dispensed: String; var billing: String; var record: String; var doses: String; var netWeight: String; var imageFiles: [String] }
struct Formula: Codable, Identifiable, Hashable { var id: String; var name: String; var content: String; var pinyin: String; var category: String; var sort: String }
struct Medicine: Codable, Identifiable, Hashable { var id: String; var name: String; var pinyin: String; var usage: String; var unit: String; var commonDose: String; var price: String; var category: String }
struct MedicinePriceLine: Identifiable { let id = UUID(); let name: String; let unit: String; let dose: Double; let price: Double; var amount: Double { dose * price } }
struct ClinicData: Codable { var patients: [Patient]; var records: [VisitRecord]; var templates: [Formula]; var medicines: [Medicine] }

private enum AppFontLevel: String, CaseIterable, Identifiable {
    case small, medium, large, extraLarge
    var id: String { rawValue }
    var title: String { switch self { case .small: "小"; case .medium: "中"; case .large: "大"; case .extraLarge: "极大" } }
    var scale: CGFloat { switch self { case .small: 1.0; case .medium: 1.22; case .large: 1.48; case .extraLarge: 1.78 } }
}
private struct AppFontScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }
private extension EnvironmentValues { var appFontScale: CGFloat { get { self[AppFontScaleKey.self] } set { self[AppFontScaleKey.self] = newValue } } }
private struct AppFontModifier: ViewModifier {
    @Environment(\.appFontScale) private var scale
    let size: CGFloat; let weight: Font.Weight
    func body(content: Content) -> some View { content.font(.system(size: size * scale, weight: weight)) }
}
private extension View { func appFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View { modifier(AppFontModifier(size: size, weight: weight)) } }

@MainActor final class ClinicStore: ObservableObject {
    private var db: OpaquePointer?
    @Published var patients: [Patient] = []; @Published var records: [VisitRecord] = []; @Published var formulas: [Formula] = []; @Published var medicines: [Medicine] = []
    @Published var search = ""; @Published var selectedPatientID: String?; @Published var selectedRecordID: String?; @Published var status = ""
    private var patientIndex: [Patient] = []; private var recordIndex: [String:[VisitRecord]] = [:]
    init() { openSQLite() }
    // The legacy Access table contains duplicate patient index rows. Merge them
    // for display while keeping every visit record in `records`.
    var uniquePatients: [Patient] { patientIndex }
    var filteredPatients: [Patient] { search.isEmpty ? patientIndex : patientIndex.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.phone.contains(search) } }
    var selectedPatient: Patient? { patients.first { $0.id == selectedPatientID } }
    var patientRecords: [VisitRecord] { recordIndex[selectedPatient?.name ?? ""] ?? [] }
    var selectedRecord: VisitRecord? { records.first { $0.id == selectedRecordID } }
    func openSQLite() {
        do {
            let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("ElectronicPrescriptionMac", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let target = dir.appendingPathComponent("clinic.sqlite")
            if !FileManager.default.fileExists(atPath: target.path), let bundled = Bundle.main.url(forResource: "clinic", withExtension: "sqlite") { try FileManager.default.copyItem(at: bundled, to: target) }
            guard sqlite3_open(target.path, &db) == SQLITE_OK else { status="数据库打开失败"; return }
            if !rows("PRAGMA table_info(visits)").contains(where: { $0.count > 1 && $0[1] == "net_weight" }) { exec("ALTER TABLE visits ADD COLUMN net_weight TEXT DEFAULT ''") }
            loadSQLite(); status="已加载 \(records.count) 条历史档案、\(formulas.count) 个常用方"
        } catch { status="数据库初始化失败：\(error.localizedDescription)" }
    }
    private func rows(_ sql: String) -> [[String]] {
        guard let db else { return [] }; var stmt: OpaquePointer?; guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }; defer { sqlite3_finalize(stmt) }; var result:[[String]]=[]
        while sqlite3_step(stmt) == SQLITE_ROW { var row:[String]=[]; for i in 0..<sqlite3_column_count(stmt) { if let p=sqlite3_column_text(stmt,i) { row.append(String(cString:p)) } else { row.append("") } }; result.append(row) }; return result
    }
    private func exec(_ sql: String) { guard let db else { status="数据库未连接"; return }; var error: UnsafeMutablePointer<CChar>?; let rc=sqlite3_exec(db, sql, nil, nil, &error); if rc != SQLITE_OK { status="数据库写入失败：\(error.map{String(cString:$0)} ?? "未知错误")"; if let error { sqlite3_free(error) } } }
    private func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "''") + "'" }
    func loadSQLite() {
        patients=rows("SELECT id,name,gender,age,medical_no,phone,address,fee_type,diagnosis,allergy FROM patients").map{Patient(id:$0[0],name:$0[1],gender:$0[2],birthOrAge:$0[3],medicalNo:$0[4],phone:$0[5],address:$0[6],feeType:$0[7],diagnosis:$0[8],allergy:$0[9])}
        records=rows("SELECT id,name,gender,age,department,visit_date,diagnosis,doctor,phone,total,visit_key,allergy,fee_type,display_date,patient_key,prescription,extra_prescription,symptoms,category,dispensed,billing,doses,net_weight FROM visits ORDER BY display_date DESC").map{ row in
            let profilePhone = patients.first(where: {$0.name.trimmingCharacters(in:.whitespacesAndNewlines) == row[1].trimmingCharacters(in:.whitespacesAndNewlines)})?.phone ?? ""
            return VisitRecord(id:row[0],name:row[1],gender:row[2],age:row[3],department:row[4],date:row[5].isEmpty ? nil : row[5],diagnosis:row[6],doctor:row[7],phone:row[8].isEmpty ? profilePhone : row[8],total:row[9],visitKey:row[10],allergy:row[11],feeType:row[12],displayDate:row[13],patientKey:row[14],prescription:row[15],extraPrescription:row[16],symptoms:row[17].contains("$") ? "" : row[17],category:row[18],dispensed:row[19],billing:row[20],record:"",doses:row[21],netWeight:row[22],imageFiles:[])
        }
        var recordIndexes: [String:Int] = [:]; for (i,r) in records.enumerated() { recordIndexes[r.id] = i }
        for row in rows("SELECT visit_id,file_name FROM visit_images") { if let i=recordIndexes[row[0]] { records[i].imageFiles.append(row[1]) } }
        formulas=rows("SELECT id,name,content,pinyin,category,sort FROM formulas").map{Formula(id:$0[0],name:$0[1],content:$0[2],pinyin:$0[3],category:$0[4],sort:$0[5])}; medicines=rows("SELECT id,name,pinyin,usage,unit,common_dose,price,category FROM medicines").map{Medicine(id:$0[0],name:$0[1],pinyin:$0[2],usage:$0[3],unit:$0[4],commonDose:$0[5],price:$0[6],category:$0[7])}; rebuildIndexes(); selectedPatientID=patients.first?.id; selectedRecordID=patientRecords.first?.id
    }
    private func rebuildIndexes() {
        var result:[Patient]=[]; var seen:[String:Int]=[:]
        for p in patients { let n=p.name.trimmingCharacters(in:.whitespacesAndNewlines); let ph=p.phone.trimmingCharacters(in:.whitespacesAndNewlines); let key=ph.isEmpty ? "name:\(n)|gender:\(p.gender)|birth:\(p.birthOrAge)" : "name:\(n)|phone:\(ph)"; if let i=seen[key] { if result[i].diagnosis.isEmpty { result[i].diagnosis=p.diagnosis }; if result[i].address.isEmpty { result[i].address=p.address } } else { seen[key]=result.count; result.append(p) } }
        var by:[String:[VisitRecord]] = [:]; for r in records { by[r.name,default:[]].append(r) }; for k in by.keys { by[k]?.sort{$0.displayDate>$1.displayDate} }; recordIndex=by
        let latest: [String:String] = by.mapValues { $0.first?.displayDate ?? "" }
        patientIndex = result.sorted { (latest[$0.name] ?? "") > (latest[$1.name] ?? "") }
    }
    func load() { openSQLite() }
    func saveAll() {
        // SQLite writes are performed by the individual create/update/delete methods.
    }
    func save(_ r: VisitRecord) {
        guard let i=records.firstIndex(where:{$0.id==r.id}) else{return}
        records[i]=r
        let exists = !rows("SELECT id FROM visits WHERE id=\(q(r.id))").isEmpty
        if exists { exec("UPDATE visits SET name=\(q(r.name)),gender=\(q(r.gender)),age=\(q(r.age)),diagnosis=\(q(r.diagnosis)),phone=\(q(r.phone)),allergy=\(q(r.allergy)),fee_type=\(q(r.feeType)),prescription=\(q(r.prescription)),symptoms=\(q(r.symptoms)),doses=\(q(r.doses)),net_weight=\(q(r.netWeight)),display_date=\(q(r.displayDate)) WHERE id=\(q(r.id))") }
        else if let pid=selectedPatientID { exec("INSERT OR IGNORE INTO patients(id,name,gender,age,phone,fee_type,allergy) VALUES(\(q(pid)),\(q(r.name)),\(q(r.gender)),\(q(r.age)),\(q(r.phone)),\(q(r.feeType)),\(q(r.allergy))); INSERT INTO visits(id,patient_id,name,gender,age,department,visit_date,diagnosis,doctor,phone,total,visit_key,allergy,fee_type,display_date,patient_key,prescription,extra_prescription,symptoms,category,dispensed,billing,doses,net_weight) VALUES(\(q(r.id)),\(q(pid)),\(q(r.name)),\(q(r.gender)),\(q(r.age)),\(q(r.department)),\(q(r.date ?? "")),\(q(r.diagnosis)),\(q(r.doctor)),\(q(r.phone)),\(q(r.total)),\(q(r.visitKey)),\(q(r.allergy)),\(q(r.feeType)),\(q(r.displayDate)),\(q(r.patientKey)),\(q(r.prescription)),\(q(r.extraPrescription)),\(q(r.symptoms)),\(q(r.category)),\(q(r.dispensed)),\(q(r.billing)),\(q(r.doses)),\(q(r.netWeight)))") }
        exec("DELETE FROM visit_images WHERE visit_id=\(q(r.id))")
        for image in r.imageFiles { exec("INSERT OR IGNORE INTO visit_images(visit_id,file_name) VALUES(\(q(r.id)),\(q(image)))") }
        if let pid = selectedPatientID, let p = patients.firstIndex(where: { $0.id == pid }) {
            patients[p].name = r.name; patients[p].gender = r.gender; patients[p].birthOrAge = r.age; patients[p].phone = r.phone; patients[p].feeType = r.feeType; patients[p].allergy = r.allergy
        }
        rebuildIndexes()
        saveAll(); status="病历已保存"
    }
    func create(patient: Patient, record: VisitRecord) {
        if !patients.contains(where: { $0.id == patient.id }) { patients.append(patient) }
        records.append(record); selectedPatientID = patient.id; selectedRecordID = record.id; saveAll(); status="新病历已保存"
    }
    func createBlankVisit(for patient: Patient) {
        let f=DateFormatter(); f.dateFormat="yyyyMMddHHmmss"; let now=f.string(from:Date())
        let display=DateFormatter(); display.dateFormat="yyyy年MM月dd日"
        let r=VisitRecord(id: now+UUID().uuidString.prefix(8), name:patient.name, gender:patient.gender, age:patient.birthOrAge, department:"全科", date:Date().ISO8601Format(), diagnosis:"", doctor:"", phone:patient.phone, total:"", visitKey:now, allergy:patient.allergy, feeType:patient.feeType, displayDate:display.string(from:Date()), patientKey:patient.name, prescription:"", extraPrescription:"", symptoms:"", category:"中医", dispensed:"", billing:"", record:"", doses:"", netWeight:"", imageFiles:[])
        if !patients.contains(where: { $0.id == patient.id }) { patients.append(patient) }
        records.append(r); rebuildIndexes(); selectedPatientID=patient.id; selectedRecordID=r.id; status="已新建空白病历，请在右侧编辑后点击保存修改"
    }
    func delete(recordID: String) {
        records.removeAll { $0.id == recordID }
        rebuildIndexes()
        exec("DELETE FROM visit_images WHERE visit_id=\(q(recordID)); DELETE FROM visits WHERE id=\(q(recordID))")
        selectedRecordID = patientRecords.first?.id
        saveAll(); status="病历已删除"
    }
    func saveFormula(name: String, content: String, existingID: String?) {
        let n=name.trimmingCharacters(in:.whitespacesAndNewlines); guard !n.isEmpty else { status="请填写处方名称"; return }
        if let id=existingID, let i=formulas.firstIndex(where:{$0.id==id}), formulas[i].name == n {
            formulas[i].content=content; exec("UPDATE formulas SET content=\(q(content)),name=\(q(n)) WHERE id=\(q(id))")
        } else {
            let id=UUID().uuidString; let f=Formula(id:id,name:n,content:content,pinyin:"",category:"个人方",sort:""); formulas.insert(f,at:0); exec("INSERT INTO formulas(id,name,content,pinyin,category,sort) VALUES(\(q(id)),\(q(n)),\(q(content)),'','个人方','')")
        }
        status="处方已保存：\(n)"
    }
    func deleteFormula(id: String) {
        formulas.removeAll { $0.id == id }; exec("DELETE FROM formulas WHERE id=\(q(id))"); status="处方已删除"
    }
    func updateMedicine(_ medicine: Medicine) {
        guard let i = medicines.firstIndex(where: { $0.id == medicine.id }) else { return }
        medicines[i] = medicine
        exec("UPDATE medicines SET name=\(q(medicine.name)),pinyin=\(q(medicine.pinyin)),usage=\(q(medicine.usage)),unit=\(q(medicine.unit)),common_dose=\(q(medicine.commonDose)),price=\(q(medicine.price)),category=\(q(medicine.category)) WHERE id=\(q(medicine.id))")
        status = "药品信息已保存"
    }
    func addMedicine(name: String, pinyin: String, usage: String, unit: String, commonDose: String, price: String, category: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { status = "请填写药品名称"; return false }
        if medicines.contains(where: { $0.name == n && $0.unit == unit }) { status = "该药品和单位已存在"; return false }
        let medicine = Medicine(id: UUID().uuidString, name: n, pinyin: pinyin, usage: usage, unit: unit, commonDose: commonDose, price: price, category: category)
        medicines.insert(medicine, at: 0)
        exec("INSERT INTO medicines(id,name,pinyin,usage,unit,common_dose,price,category) VALUES(\(q(medicine.id)),\(q(n)),\(q(pinyin)),\(q(usage)),\(q(unit)),\(q(commonDose)),\(q(price)),\(q(category)))")
        status = "药品已新增：\(n)"
        return true
    }
    func deleteMedicine(id: String) {
        guard let medicine = medicines.first(where: { $0.id == id }) else { return }
        medicines.removeAll { $0.id == id }
        exec("DELETE FROM medicines WHERE id=\(q(id))")
        status = "药品已删除：\(medicine.name)"
    }
}

struct NewMedicineView: View {
    @ObservedObject var store: ClinicStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var pinyin = ""; @State private var usage = ""; @State private var unit = "g"; @State private var commonDose = ""; @State private var price = ""; @State private var category = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新增药品").appFont(20, weight: .bold)
            TextField("药品名称（必填）", text: $name)
            HStack { TextField("拼音", text: $pinyin); TextField("单位，例如 g / 袋 / 盒", text: $unit) }
            HStack { TextField("常用剂量", text: $commonDose); TextField("单价（元）", text: $price) }
            HStack { TextField("用法", text: $usage); TextField("分类", text: $category) }
            HStack { Spacer(); Button("取消") { dismiss() }; Button("新增") { if store.addMedicine(name: name, pinyin: pinyin, usage: usage, unit: unit, commonDose: commonDose, price: price, category: category) { dismiss() } }.buttonStyle(.borderedProminent) }
        }.padding().frame(width: 520)
    }
}

struct MedicineManagerView: View {
    @ObservedObject var store: ClinicStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var drafts: [String: Medicine] = [:]
    @State private var showingNewMedicine = false
    @State private var medicineToDelete: Medicine?
    @State private var confirmDeleteMedicine = false
    var filtered: [Medicine] {
        let key = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? store.medicines : store.medicines.filter { $0.name.localizedCaseInsensitiveContains(key) || $0.pinyin.localizedCaseInsensitiveContains(key) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("药品商品价格").appFont(20, weight: .bold); Spacer(); TextField("搜索药品名称 / 拼音", text: $search).textFieldStyle(.roundedBorder).frame(width: 260); Button("新增药品") { showingNewMedicine = true }.buttonStyle(.borderedProminent); Button("完成") { dismiss() } }
            Text("修改价格后点击右侧保存。中药饮片通常按数据库中的单位（如 g）计价。").appFont(11).foregroundStyle(.secondary)
            List(filtered) { medicine in
                let value = drafts[medicine.id] ?? medicine
                HStack(spacing: 12) {
                    VStack(alignment: .leading) { Text(value.name); Text("\(value.usage)  ·  \(value.unit)").appFont(11).foregroundStyle(.secondary) }
                    Spacer()
                    TextField("价格", text: Binding(get: { value.price }, set: { var v = drafts[medicine.id] ?? medicine; v.price = $0; drafts[medicine.id] = v })).frame(width: 90)
                    Text("元 / \(value.unit)").appFont(11).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                    Button("保存") { store.updateMedicine(drafts[medicine.id] ?? medicine); drafts[medicine.id] = nil }
                    Button("删除", role: .destructive) { medicineToDelete = medicine; confirmDeleteMedicine = true }
                }.padding(.vertical, 3)
            }
        }.padding().frame(minWidth: 820, minHeight: 560)
        .sheet(isPresented: $showingNewMedicine) { NewMedicineView(store: store) }
        .alert("删除这个药品？", isPresented: $confirmDeleteMedicine) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { if let medicine = medicineToDelete { drafts[medicine.id] = nil; store.deleteMedicine(id: medicine.id) }; medicineToDelete = nil }
        } message: {
            Text(medicineToDelete.map { "将删除“\($0.name)”（\($0.unit)）的价格资料，不会修改历史处方内容。" } ?? "")
        }
    }
}

struct ContentView: View {
    @StateObject private var store=ClinicStore(); @State private var showingNewVisit=false; @State private var showingMedicineManager=false; @State private var showingFontSettings=false; @State private var confirmDelete=false
    @AppStorage("appFontLevel") private var storedFontLevel = AppFontLevel.small.rawValue
    var selectedRecord: VisitRecord? { store.selectedRecord }
    var body: some View {
        NavigationSplitView {
            VStack(alignment:.leading,spacing:8) {
                Text("患者历史").appFont(20, weight: .bold); TextField("姓名 / 电话",text:$store.search).textFieldStyle(.roundedBorder)
                List(store.filteredPatients,selection:$store.selectedPatientID){p in VStack(alignment:.leading){Text(p.name).appFont(13, weight: .semibold);Text("\(p.gender)  \(p.phone)").appFont(11).foregroundStyle(.secondary)}.tag(p.id)}
                Divider(); Text("历史病历").appFont(13, weight: .semibold).padding(.horizontal,4)
                List(store.patientRecords,selection:$store.selectedRecordID){r in HStack{VStack(alignment:.leading){Text(r.displayDate.isEmpty ? (r.date ?? "未注明日期") : r.displayDate);Text(r.diagnosis.isEmpty ? "未填写诊断" : r.diagnosis).appFont(11)};Spacer();Image(systemName:"chevron.right").appFont(11).foregroundStyle(.secondary)}.tag(r.id).contextMenu { Button("删除病历", role:.destructive){store.selectedRecordID=r.id;confirmDelete=true} }}
                Text(store.status).appFont(11).foregroundStyle(.secondary)
                Button { showingFontSettings = true } label: { HStack { Label("字体大小", systemImage: "textformat.size"); Spacer(); Text((AppFontLevel(rawValue: storedFontLevel) ?? .small).title).foregroundStyle(.secondary) } }.buttonStyle(.bordered)
            }.padding().navigationSplitViewColumnWidth(min:300,ideal:360)
        } detail: { if let r=selectedRecord { EditorView(record:r,store:store).id(r.id) } else { VStack{Image(systemName:"doc.text").appFont(26);Text("请选择历史病历")}.foregroundStyle(.secondary) } }.frame(minWidth:1200,minHeight:760)
        .onChange(of: store.selectedPatientID) { _ in store.selectedRecordID = store.patientRecords.first?.id }
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { showingFontSettings = true } label: { Label("字体设置", systemImage: "textformat.size") } }; ToolbarItem(placement: .primaryAction) { Button { showingMedicineManager = true } label: { Label("药品价格", systemImage: "dollarsign.circle") } }; ToolbarItem(placement: .primaryAction) { Button { showingNewVisit = true } label: { Label("新建病历", systemImage: "plus") } }; ToolbarItem(placement: .primaryAction) { Button { confirmDelete = true } label: { Label("删除病历", systemImage: "trash") }.disabled(store.selectedRecordID == nil) } }
        .sheet(isPresented: $showingNewVisit) { NewVisitView(store: store) }
        .sheet(isPresented: $showingMedicineManager) { MedicineManagerView(store: store) }
        .sheet(isPresented: $showingFontSettings) { FontSettingsView() }
        .alert("删除这条历史病历？", isPresented:$confirmDelete) { Button("取消", role:.cancel){}; Button("删除", role:.destructive){ if let id=store.selectedRecordID { store.delete(recordID:id) } } } message: { Text("删除后不会影响患者档案，但这条就诊记录将从历史中移除。") }
    }
}

private func calculatePrescription(_ text: String, dosesText: String, medicines: [Medicine]) -> ([MedicinePriceLine], Double) {
    struct Candidate { let medicine: Medicine; let range: NSRange }
    let source = text.lowercased() as NSString
    let ordered = medicines.filter { !$0.name.isEmpty }.sorted { $0.name.count > $1.name.count }
    var candidates: [Candidate] = []
    for medicine in ordered {
        let needle = medicine.name.lowercased() as NSString
        var start = 0
        while start < source.length {
            let found = source.range(of: needle as String, options: [], range: NSRange(location: start, length: source.length - start))
            if found.location == NSNotFound { break }
            candidates.append(Candidate(medicine: medicine, range: found))
            start = found.location + max(found.length, 1)
        }
    }
    // Prefer the longest name when one medicine name is contained in another (白参/白参须).
    candidates.sort {
        if $0.range.location != $1.range.location { return $0.range.location < $1.range.location }
        let tail0 = source.substring(with: NSRange(location: $0.range.location + $0.range.length, length: min(10, source.length - $0.range.location - $0.range.length)))
        let tail1 = source.substring(with: NSRange(location: $1.range.location + $1.range.length, length: min(10, source.length - $1.range.location - $1.range.length)))
        let unit0 = !$0.medicine.unit.isEmpty && tail0.contains($0.medicine.unit.lowercased())
        let unit1 = !$1.medicine.unit.isEmpty && tail1.contains($1.medicine.unit.lowercased())
        if unit0 != unit1 { return unit0 }
        return $0.range.length > $1.range.length
    }
    var occupied: [NSRange] = []
    var result: [MedicinePriceLine] = []
    for candidate in candidates {
        if occupied.contains(where: { NSIntersectionRange($0, candidate.range).length > 0 }) { continue }
        occupied.append(candidate.range)
        let tailStart = candidate.range.location + candidate.range.length
        let tailLength = min(18, source.length - tailStart)
        guard tailLength > 0 else { continue }
        let tail = source.substring(with: NSRange(location: tailStart, length: tailLength))
        guard let numberRange = tail.range(of: "[0-9]+(?:\\.[0-9]+)?", options: .regularExpression), let dose = Double(tail[numberRange]) else { continue }
        let price = Double(candidate.medicine.price.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        result.append(MedicinePriceLine(name: candidate.medicine.name, unit: candidate.medicine.unit, dose: dose, price: price))
    }
    let count = Double(dosesText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1
    return (result, result.reduce(0) { $0 + $1.amount } * max(count, 1))
}

private struct EditorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).appFont(14, weight: .semibold)
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.055)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EditorView: View {
    let record: VisitRecord; @ObservedObject var store: ClinicStore; @State private var formulaSearch=""; @State private var formulaName=""; @State private var selectedFormulaID:String?; @State private var confirmDeleteFormula=false; @State private var saveFormulaMessage=""; @State private var showFormulaMessage=false; @State private var draft:VisitRecord; @State private var symptomsExpanded = false; @State private var pricingExpanded = false
    init(record:VisitRecord,store:ClinicStore){self.record=record;self.store=store;_draft=State(initialValue:record)}
    private func infoField(_ title: String, text: Binding<String>, width: CGFloat) -> some View {
        HStack(spacing: 8) { Text(title + "：").fixedSize(); TextField("", text: text).textFieldStyle(.plain).frame(width: width, alignment: .leading) }
    }
    var filteredFormulas: [Formula] {
        let key = formulaSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { return Array(store.formulas.prefix(40)) }
        let isPinyinQuery = key.range(of: "^[A-Za-z]+$", options: .regularExpression) != nil
        if isPinyinQuery {
            // Latin input only searches the formula name itself, not its Chinese pinyin.
            // For example, "D" matches names containing an actual D/d character.
            return store.formulas.filter {
                $0.name
                    .localizedCaseInsensitiveContains(key)
            }
        }
        // Chinese input is a keyword match against the formula name.
        return store.formulas.filter { $0.name.localizedCaseInsensitiveContains(key) }
    }
    var body: some View {
        let pricing = pricingExpanded ? calculatePrescription(draft.prescription, dosesText: draft.doses, medicines: store.medicines) : ([], 0.0)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                EditorSection(title: "患者信息") {
                    HStack(spacing: 32) {
                        infoField("姓名", text:$draft.name, width:180)
                        infoField("性别", text:$draft.gender, width:80)
                        infoField("年龄", text:$draft.age, width:80)
                        Spacer(minLength:0)
                    }
                    Divider()
                    HStack(spacing:8) { Text("电话：").fixedSize(); TextField("",text:$draft.phone).textFieldStyle(.plain).frame(width:260,alignment:.leading); Spacer() }
                    Divider()
                    HStack(spacing:24) { HStack(spacing:8){Text("就诊日期：");Text(draft.displayDate.isEmpty ? (draft.date ?? "") : draft.displayDate)}; HStack(spacing:8){Text("科别：");Text(draft.department)}; Spacer() }
                }
                EditorSection(title: "病历") {
                    HStack(spacing:8) { Text("诊断：").fixedSize(); TextField("",text:$draft.diagnosis).textFieldStyle(.plain); }
                    Divider()
                    HStack { Text("症状/主诉：").appFont(13,weight:.semibold); Spacer(); Text(draft.symptoms.isEmpty ? "未填写" : "已填写").foregroundStyle(.secondary) }
                    ZStack(alignment:.bottomTrailing) {
                        TextEditor(text:$draft.symptoms).frame(minHeight:symptomsExpanded ? 260:58,maxHeight:symptomsExpanded ? 360:76).padding(6).background(Color(nsColor:.textBackgroundColor)).overlay(RoundedRectangle(cornerRadius:6).stroke(Color(nsColor:.separatorColor)))
                        Button(symptomsExpanded ? "收起":"展开"){withAnimation(.easeInOut){symptomsExpanded.toggle()}}.appFont(11).buttonStyle(.borderless).padding(.trailing,10).padding(.bottom,7)
                    }
                }
                EditorSection(title: "快速选方") {
                    TextField("搜索方名 / 拼音",text:$formulaSearch)
                    ScrollView(.horizontal){HStack{ForEach(filteredFormulas.prefix(12)){f in Button(f.name){selectedFormulaID=f.id;formulaName=f.name;draft.prescription=f.content}}}}
                    HStack { TextField("处方名称（保存时填写）",text:$formulaName); Button("保存处方"){let n=formulaName.trimmingCharacters(in:.whitespacesAndNewlines);if n.isEmpty{saveFormulaMessage="请先填写处方名称"}else{store.saveFormula(name:n,content:draft.prescription,existingID:selectedFormulaID);saveFormulaMessage=store.status};showFormulaMessage=true}.buttonStyle(.borderedProminent);Button("删除处方",role:.destructive){confirmDeleteFormula=true}.disabled(selectedFormulaID==nil) }
                    TextEditor(text:$draft.prescription).frame(minHeight:170).padding(4).background(Color(nsColor:.textBackgroundColor)).overlay(RoundedRectangle(cornerRadius:6).stroke(Color(nsColor:.separatorColor)))
                    HStack(spacing:8) { Text("剂数：").fixedSize(); TextField("请输入剂数",text:$draft.doses).frame(width:180); Spacer() }
                    Text(store.status).appFont(11).foregroundStyle(.secondary)
                }
                VStack(alignment:.leading,spacing:8) {
                    HStack { Text("处方划价").appFont(13,weight:.semibold);Spacer();Button(pricingExpanded ? "收起":"划价"){pricingExpanded.toggle()}.buttonStyle(.borderedProminent) }
                    if pricingExpanded { VStack(alignment:.leading,spacing:8) { if pricing.0.isEmpty { Text("暂未识别到带剂量的药品。").foregroundStyle(.secondary) } else { let typeCount=Set(pricing.0.map{"\($0.name)|\($0.unit)"}).count;Text("识别到 \(typeCount) 种药物").appFont(11).foregroundStyle(.secondary);ForEach(pricing.0){line in HStack{Text(line.name);Spacer();if line.price>0{Text(String(format:"%.2f %@ × %.3f元 = %.2f元",line.dose,line.unit,line.price,line.amount))}}};HStack{Spacer();Text("合计（\(draft.doses.isEmpty ? "1":draft.doses)剂）").bold();Text(String(format:"¥%.2f",pricing.1)).bold().foregroundStyle(.blue)}} }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:10)) }
                }.frame(maxWidth:.infinity)
                EditorSection(title:"病历图片") {
                    ImageGallery(files:draft.imageFiles,editable:true,onAdd:{draft.imageFiles.append(contentsOf:chooseImages())},onDelete:{name in draft.imageFiles.removeAll{$0==name}})
                    Divider()
                    HStack(spacing:8) { Text("净重：").fixedSize(); TextField("请输入数值",text:$draft.netWeight).frame(width:180); Text("g").foregroundStyle(.secondary); Spacer() }
                }
                HStack { Button("保存修改"){store.save(draft)}.keyboardShortcut("s");Button("恢复原内容"){draft=record};Text("处方类别：\(draft.category)").foregroundStyle(.secondary);Spacer() }.padding(12).frame(maxWidth:.infinity).background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:10))
            }.padding(20).frame(maxWidth:.infinity,alignment:.leading)
        }
        .navigationTitle("门诊电子处方 · 病历编辑")
        .alert("删除这个处方？",isPresented:$confirmDeleteFormula){Button("取消",role:.cancel){};Button("删除",role:.destructive){if let id=selectedFormulaID{store.deleteFormula(id:id);selectedFormulaID=nil;formulaName=""}}}message:{Text("删除不会影响已经保存到历史病历中的处方内容。")}
        .alert("保存处方",isPresented:$showFormulaMessage){Button("确定",role:.cancel){}}message:{Text(saveFormulaMessage)}
    }
}

@MainActor private func chooseImages() -> [String] {
    if imagePasteRequested { imagePasteRequested = false; return saveClipboardImages() }
    let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false; panel.allowedContentTypes = [.image]
    guard panel.runModal() == .OK else { return [] }
    let fm = FileManager.default
    let dir = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))!.appendingPathComponent("ElectronicPrescriptionMac/images")
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return panel.urls.compactMap { url in let name = UUID().uuidString + "-" + url.lastPathComponent; let dst=dir.appendingPathComponent(name); do { try fm.copyItem(at:url,to:dst); return name } catch { return nil } }
}

@MainActor private var imagePasteRequested = false
@MainActor private func saveClipboardImages() -> [String] {
    var images: [NSImage] = []
    if let values = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] { images.append(contentsOf: values) }
    if images.isEmpty, let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL] { images = urls.compactMap { NSImage(contentsOf: $0 as URL) } }
    let fm = FileManager.default
    let dir = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))!.appendingPathComponent("ElectronicPrescriptionMac/images")
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return images.compactMap { image in
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let name = UUID().uuidString + "-pasted.png"; let url = dir.appendingPathComponent(name)
        do { try data.write(to: url); return name } catch { return nil }
    }
}

struct ImageGallery: View {
    let files: [String]; var editable=false; var onAdd: () -> Void = {}; var onDelete: (String) -> Void = { _ in }
    @State private var selected: URL?
    private var imageDirectory: URL { Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("图片资料") }
    var body: some View {
        VStack(alignment: .leading) { ScrollView(.horizontal) { HStack(spacing: 10) { ForEach(files, id: \.self) { name in if let url = imageURL(name), let ns = NSImage(contentsOf: url) { ZStack(alignment:.topTrailing) { Button { selected = url } label: { Image(nsImage: ns).resizable().scaledToFill().frame(width: 120, height: 90).clipped().cornerRadius(5) }.buttonStyle(.plain); if editable { Button { onDelete(name) } label: { Image(systemName:"xmark.circle.fill").foregroundStyle(.red).background(.white, in:Circle()) }.buttonStyle(.plain).padding(3) } } } }; if editable { HStack { Button { imagePasteRequested = false; onAdd() } label: { Label("上传图片", systemImage:"plus") }.buttonStyle(.bordered); Button { imagePasteRequested = true; onAdd() } label: { Label("粘贴图片", systemImage:"doc.on.clipboard") }.buttonStyle(.bordered) } } } }.frame(minHeight: 100, maxHeight: 120); if files.isEmpty { Text("此病历没有关联图片").foregroundStyle(.secondary) } }.sheet(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) { if let url = selected { VStack { Image(nsImage: NSImage(contentsOf: url) ?? NSImage()).resizable().scaledToFit().padding(); Text(url.lastPathComponent).appFont(11) }.frame(minWidth: 700, minHeight: 500).padding() } }
    }
    private func imageURL(_ name: String) -> URL? { let support = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first!.appendingPathComponent("ElectronicPrescriptionMac/images").appendingPathComponent(name); if FileManager.default.fileExists(atPath:support.path) { return support }; let u=imageDirectory.appendingPathComponent(name); return FileManager.default.fileExists(atPath:u.path) ? u : nil }
}

struct NewVisitView: View {
    @ObservedObject var store: ClinicStore; @Environment(\.dismiss) private var dismiss
    @State private var query=""
    var matches: [Patient] { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : store.uniquePatients.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.phone.contains(query) }.prefix(10).map { $0 } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("新建病历").appFont(20, weight: .bold)
            Text("先选择患者；选择后会立即新增一条空白历史病历，并在右侧编辑。") .foregroundStyle(.secondary)
            TextField("输入姓名或电话", text: $query).textFieldStyle(.roundedBorder)
            if !matches.isEmpty {
                Text("匹配到的患者").appFont(13, weight: .semibold)
                List(matches) { p in Button { dismiss(); DispatchQueue.main.async { store.createBlankVisit(for: p) } } label: { HStack { Text(p.name).bold(); Text(p.gender); Text(p.phone).foregroundStyle(.secondary); Spacer(); Image(systemName: "chevron.right") } } }
            }
            Button("＋ 新建此患者") { createNew() }.disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            HStack { Spacer(); Button("取消") { dismiss() } }
        }.padding().frame(width: 430, height: 330)
    }
    private func createNew() {
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines); guard !name.isEmpty else { return }
        let p = Patient(id: UUID().uuidString, name: name, gender: "", birthOrAge: "", medicalNo: "", phone: "", address: "", feeType: "自费", diagnosis: "", allergy: "")
        dismiss(); DispatchQueue.main.async { store.createBlankVisit(for: p) }
    }
}

private struct FontSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appFontLevel") private var storedLevel = AppFontLevel.small.rawValue
    private var level: Binding<AppFontLevel> { Binding(get: { AppFontLevel(rawValue: storedLevel) ?? .small }, set: { storedLevel = $0.rawValue }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("字体大小").appFont(20, weight: .bold)
            Text("选择后立即应用到整个软件，并自动保存设置。当前默认大小为“小”。").foregroundStyle(.secondary)
            Picker("字体大小", selection: level) { ForEach(AppFontLevel.allCases) { item in Text(item.title).tag(item) } }.pickerStyle(.segmented)
            GroupBox("预览") { VStack(alignment: .leading, spacing: 8) { Text("患者姓名与病历内容").appFont(13, weight: .semibold); Text("处方：黄芪10g  当归10g  白术10g"); Button("示例按钮") {} }.frame(maxWidth: .infinity, alignment: .leading).padding(8) }
            HStack { Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 520)
    }
}

private struct AppFontRootModifier: ViewModifier {
    @AppStorage("appFontLevel") private var storedLevel = AppFontLevel.small.rawValue
    private var scale: CGFloat { (AppFontLevel(rawValue: storedLevel) ?? .small).scale }
    func body(content: Content) -> some View {
        content
            .environment(\.appFontScale, scale)
            .font(.system(size: 13 * scale))
            .environment(\.defaultMinListRowHeight, 24 * scale)
    }
}

@main struct ElectronicPrescriptionMacApp: App {
    var body: some Scene {
        WindowGroup { ContentView().modifier(AppFontRootModifier()) }
        Settings { FontSettingsView().modifier(AppFontRootModifier()) }
    }
}
